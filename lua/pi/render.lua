-- Chat buffer rendering.
--
-- The chat buffer holds ONLY message content; every bit of box chrome (left
-- bar, borders, role label, row background) lives in extmarks, so yank/copy of
-- the transcript stays clean. Layout model:
--
--   * a box = a contiguous buffer range [start0, end0) painted with one `STYLES`
--     palette. `bubbles[buf]` is the Lua-side registry of painted boxes; jump /
--     resize / collapse read it instead of extmark rows (those drift when a line
--     carrying virt_lines is rewritten via nvim_buf_set_lines).
--   * each box owns its own extmark namespace (`pi_box_<n>`, see new_ns);
--     repainting = wipe that namespace and redraw, immune to the drift above.
--   * boxes that are still streaming (thinking / assistant text / tool batches)
--     are held in `*_box` handles and grown with grow_box().
--
-- Hard invariants — break these and the border visually falls apart:
--   * box width (inner + side borders) + sign column must equal the window's
--     text area: one cell wider and the right border wraps onto the next row
--     (bubble_inner_width / fixed_signcol_width).
--   * no buffer line inside a box may exceed the box width: nvim cannot draw
--     virt_text on wrapped segments, so an over-long line loses its side
--     borders on continuation rows. All boxed content is hard-wrapped via
--     wrap_line at append time (append_wrapped_line / append_text_delta).
--   * tool collapse ×N keys on the rendered block text, so identical calls
--     stay stable even after wrapping/capping (upsert_tool_end).
local M = {}

local Rtext = require("pi.render.text")
local Rtools = require("pi.render.tools")
local disp_w = Rtext.disp_w
local rep_to_width = Rtext.rep_to_width
local wrap_line = Rtext.wrap_line
local cap_lines = Rtext.cap_lines
local is_md_table_row = Rtext.is_md_table_row
local split_md_cells = Rtext.split_md_cells
local is_md_sep_row = Rtext.is_md_sep_row
local align_md_table = Rtext.align_md_table
local collapse_tool_lines = Rtools.collapse_tool_lines
local collapse_thinking_lines = Rtools.collapse_thinking_lines

-- pending tools by toolCallId → { name, detail, line }
local pending = {}
-- last compact tool summary for collapse: { name, detail, count, line_idx }
local last_tool = nil
local streaming_assistant = false
local streaming_thinking = false
--- After a streamed "\n", the next delta starts a new buffer line (do not merge).
local stream_at_bol = false
local follow_scheduled = false
--- Cleared only by gg; content updates always force-follow while true
local stick_bottom = true
--- Ignore WinScrolled until this hrtime
local suppress_until = 0
local scroll_autocmd ---@type integer|nil
--- buf → history state from sessions.open_history (nil once fully loaded)
local history_by_buf = {}
local OLDER_MARK = "↑ 更早的对话 · 滚到顶或 gg 加载"
--- Text-level decoration (thinking gray text, error red, legacy you bar)
local role_ns = vim.api.nvim_create_namespace("pi_role")
local in_you_body = false
local in_thinking_body = false

--- One box shape+palette per role so user / tool / thinking are told apart at a glance
local STYLES = {
  user = {
    label = "user",
    label_hl = "PiYou",
    tl = "╭",
    tr = "╮",
    bl = "╰",
    br = "╯",
    h = "─",
    v = "│",
    bar = "▌",
    bar_hl = "PiYouBar",
    border_hl = "PiYouBorder",
    body_hl = "PiYouBubble",
  },
  tool = {
    label = "toolcall",
    label_hl = "PiAgent",
    tl = "┌",
    tr = "┐",
    bl = "└",
    br = "┘",
    h = "─",
    v = "│",
    bar = "▌",
    bar_hl = "PiToolBar",
    border_hl = "PiToolBorder",
    body_hl = "PiToolBubble",
  },
  thinking = {
    label = "thinking",
    label_hl = "PiThinking",
    tl = "╭",
    tr = "╮",
    bl = "╰",
    br = "╯",
    h = "┄",
    v = "┊",
    bar = "▏",
    bar_hl = "PiThinkBar",
    border_hl = "PiThinkBorder",
    body_hl = "PiThinkBubble",
  },
  -- Final answer: same ▌│ chrome widths as toolcall so body text shares columns.
  -- Label is set per-box to the turn number ("#1", "#2", …) via make_assistant_style.
  assistant = {
    label = "",
    label_hl = "PiAssistant",
    tl = "╭",
    tr = "╮",
    bl = "╰",
    br = "╯",
    h = "─",
    v = "│",
    bar = "▌",
    bar_hl = "PiAsstBar",
    border_hl = "PiAsstBorder",
    body_hl = "PiAsstBubble",
  },
}

--- bufnr → { { buf, ns, start0, end0, style }, ... } end0 exclusive
local bubbles = {}
--- boxes still being streamed: { buf, box }
local tool_box = nil
local think_box = nil
local asst_box = nil
local box_seq = 0
local bubble_resize_autocmd ---@type integer|nil

--- 每个 box 独占一个 extmark namespace，重绘 = 清空整个 namespace 再画。
--- 按行范围清是不可靠的：virt_lines + nvim_buf_set_lines 会平移被改写行的
--- 存储行号，导致旧 mark 清不掉、每次流式 delta 都会残留堆积。
local function new_ns()
  box_seq = box_seq + 1
  return vim.api.nvim_create_namespace("pi_box_" .. box_seq)
end

--- Fixed sign-column width when `textoff` is 0. `auto`/`auto:N` only grow when a
--- sign is present (textoff already reflects that), so inventing a cell here made
--- boxes one cell too narrow and left a gap next to `┌`/`└`.
local function fixed_signcol_width(win)
  local sc = tostring(vim.wo[win].signcolumn)
  if sc == "no" then
    return 0
  end
  local n = tonumber(sc:match("^yes:(%d+)$"))
  if n then
    return n
  end
  if sc == "yes" then
    return 2
  end
  return 0
end

--- Display widths of box chrome for a style. With ambiwidth=double (common in
--- CJK setups) bar/│/─ are 2 cells each — never hard-code 1.
local function style_chrome(style)
  local bar_w = (style.bar and style.bar ~= "") and disp_w(style.bar) or 0
  local side_w = disp_w(style.v)
  return bar_w, side_w
end

--- Text-area width of the last window the chat was painted in. Blocks are also
--- rendered into scratch buffers (history paging) where there is no window to
--- measure, and the chat window can be much narrower than the screen (todo
--- sidebar), so remember the real width instead of guessing from `columns`.
local last_avail = nil

local function bubble_avail(buf)
  local wins = vim.fn.win_findbuf(buf)
  local avail
  if wins[1] then
    local win = wins[1]
    local info = vim.fn.getwininfo(win)[1]
    local width = (info and info.width) or vim.api.nvim_win_get_width(win)
    local off = (info and info.textoff) or 0
    -- prefer textoff; if it reports 0, only subtract a *fixed* yes:N gutter
    avail = width - (off > 0 and off or fixed_signcol_width(win))
    last_avail = avail
  else
    -- no window here (scratch buffer, or the chat is closed): reuse the width the
    -- chat window had, and stay narrower than the screen when we never saw one
    avail = last_avail or (vim.o.columns - 4)
  end
  return avail
end

--- Inner stretch width: avail − bar − left side − right side.
local function bubble_inner_width(buf, style)
  local avail = bubble_avail(buf)
  local bar_w, side_w = 1, 1
  if style then
    bar_w, side_w = style_chrome(style)
  end
  return math.max(10, avail - bar_w - 2 * side_w), avail
end

--- Realign the contiguous markdown table ending at `end0` (0-based exclusive).
local function realign_md_table_at(buf, end0, pad)
  pad = pad or ""
  local pad_w = disp_w(pad)
  local n = vim.api.nvim_buf_line_count(buf)
  end0 = math.min(end0 or n, n)
  -- skip trailing blanks so a final "\n" does not hide the table
  while end0 > 0 do
    local line = vim.api.nvim_buf_get_lines(buf, end0 - 1, end0, false)[1] or ""
    if vim.trim(line) ~= "" then
      break
    end
    end0 = end0 - 1
  end
  if end0 <= 0 then
    return
  end
  local start0 = end0 - 1
  while start0 >= 0 do
    local line = vim.api.nvim_buf_get_lines(buf, start0, start0 + 1, false)[1] or ""
    if not is_md_table_row(line) then
      break
    end
    start0 = start0 - 1
  end
  start0 = start0 + 1
  if end0 - start0 < 2 then
    return
  end
  local raw = vim.api.nvim_buf_get_lines(buf, start0, end0, false)
  local stripped = {}
  local has_sep = false
  for _, line in ipairs(raw) do
    local body = line
    if pad_w > 0 and #pad > 0 and line:sub(1, #pad) == pad then
      body = line:sub(#pad + 1)
    else
      body = vim.trim(line)
    end
    stripped[#stripped + 1] = body
    if is_md_sep_row(split_md_cells(body)) then
      has_sep = true
    end
  end
  if not has_sep then
    return
  end
  local aligned = align_md_table(stripped)
  local out = {}
  for _, line in ipairs(aligned) do
    out[#out + 1] = pad .. line
  end
  -- caller must hold with_write (or buffer writable)
  vim.api.nvim_buf_set_lines(buf, start0, end0, false, out)
end

--- Append box `b` to the buffer's box list (registry order = paint order).
local function push_bubble(buf, b)
  local list = bubbles[buf]
  if not list then
    list = {}
    bubbles[buf] = list
  end
  list[#list + 1] = b
end

--- Top rule with the role label tucked into its left corner:
--- `▌╭─ user ───────╮` / `▏╭┄ thinking ┄ ftk ┄╮` / `▌┌─ toolcall ── ftc ─┐`
--- Left bar is virt_text (same column as the box), not signcolumn — signs sit
--- outside the text area and made `▌` stick out past `┌`/`└`.
--- Horizontal fill uses display width so ambiwidth=double / CJK does not blow
--- past the window and leave the right corner unclosed.
---@param fold_hint string|nil e.g. "ftc" / "ftk" shown on the right of the top rule
local function top_rule(style, inner, fold_hint)
  local chunks = {}
  if style.bar and style.bar ~= "" then
    chunks[#chunks + 1] = { style.bar, style.bar_hl }
  end
  local label = style.label
  local hint = ""
  if fold_hint and fold_hint ~= "" then
    hint = " " .. fold_hint .. " "
  end
  if not label or label == "" then
    chunks[#chunks + 1] = { style.tl .. rep_to_width(style.h, inner) .. style.tr, style.border_hl }
    return chunks
  end
  local head = style.h .. " "
  local mid = " "
  local used = disp_w(head .. label .. mid .. hint)
  if used >= inner then
    -- too narrow for hint — keep label only
    used = disp_w(head .. label .. mid)
    if used >= inner then
      chunks[#chunks + 1] = { style.tl .. rep_to_width(style.h, inner) .. style.tr, style.border_hl }
      return chunks
    end
    hint = ""
  end
  local fill = inner - used
  chunks[#chunks + 1] = { style.tl .. head, style.border_hl }
  chunks[#chunks + 1] = { label, style.label_hl }
  chunks[#chunks + 1] = { mid .. rep_to_width(style.h, fill), style.border_hl }
  if hint ~= "" then
    chunks[#chunks + 1] = { hint, style.label_hl }
  end
  chunks[#chunks + 1] = { style.tr, style.border_hl }
  return chunks
end

--- Bottom rule; mirrors top_rule's left bar so `▌└…┘` corners stay flush.
local function bottom_rule(style, inner)
  local chunks = {}
  if style.bar and style.bar ~= "" then
    chunks[#chunks + 1] = { style.bar, style.bar_hl }
  end
  chunks[#chunks + 1] = { style.bl .. rep_to_width(style.h, inner) .. style.br, style.border_hl }
  return chunks
end

--- Paint one boxed row: left bar + bg + side borders + top/bottom rule
local function paint_row(buf, ns, row, line, style, inner, avail, is_first, is_last, fold_hint)
  local _, side_w = style_chrome(style)
  local left = {}
  if style.bar and style.bar ~= "" then
    left[#left + 1] = { style.bar, style.bar_hl }
  end
  -- space after │ is part of the inner area (always 1 cell)
  left[#left + 1] = { style.v .. " ", style.border_hl }
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
    line_hl_group = style.body_hl,
    virt_text = left,
    virt_text_pos = "inline",
    priority = 10,
  })
  -- pin right border to the window edge; repeat on soft-wrapped screen rows
  -- (without repeat_linebreak, only the first visual row gets │)
  local right_col = math.max(0, avail - side_w)
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
    virt_text = { { style.v, style.border_hl } },
    virt_text_pos = "overlay",
    virt_text_win_col = right_col,
    virt_text_repeat_linebreak = true,
    priority = 11,
  })
  if is_first then
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
      virt_lines = { top_rule(style, inner, fold_hint) },
      virt_lines_above = true,
      priority = 12,
    })
  end
  if is_last then
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
      virt_lines = { bottom_rule(style, inner) },
      virt_lines_above = false,
      priority = 12,
    })
  end
end

local function fold_hint_for(b)
  if not b or not b.style then
    return nil
  end
  if b.style.bar_hl == "PiToolBar" and b.tool_full then
    return "ftc"
  end
  if b.style.bar_hl == "PiThinkBar" and b.fold_full then
    return "ftk"
  end
  -- streaming thinking (not yet finalized) still hints ftk
  if b.style.bar_hl == "PiThinkBar" then
    return "ftk"
  end
  if b.style.bar_hl == "PiToolBar" then
    return "ftc"
  end
  return nil
end

--- Redraw one box from scratch. O(box rows) per call: only streaming boxes repaint
--- often, and they stay short (thinking paragraphs). Batches are painted once.
local function paint_box(b)
  local buf = b.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  pcall(vim.api.nvim_buf_clear_namespace, buf, b.ns, 0, -1)
  if b.end0 <= b.start0 then
    return
  end
  local inner, avail = bubble_inner_width(buf, b.style)
  local lines = vim.api.nvim_buf_get_lines(buf, b.start0, b.end0, false)
  local hint = fold_hint_for(b)
  for i, line in ipairs(lines) do
    local row = b.start0 + i - 1
    paint_row(buf, b.ns, row, line, b.style, inner, avail, row == b.start0, i == #lines, hint)
  end
end

local function close_tool_batch()
  tool_box = nil
end

local function close_thinking_box()
  think_box = nil
end

local function close_assistant_box()
  asst_box = nil
end

local function is_assistant_style(style)
  return style and style.bar_hl == "PiAsstBar"
end

--- How many final-answer boxes already exist in this buffer (chronological).
local function count_assistant_boxes(buf)
  local n = 0
  for _, b in ipairs(bubbles[buf] or {}) do
    if is_assistant_style(b.style) then
      n = n + 1
    end
  end
  return n
end

--- 为 assistant 样式做一份副本，左上角写轮次序号（与 "toolcall" 同一槽位）。
local function make_assistant_style(buf)
  local s = vim.tbl_extend("force", {}, STYLES.assistant)
  s.label = "#" .. tostring(count_assistant_boxes(buf) + 1)
  return s
end

--- After prepending history, renumber answer boxes #1..#N by buffer order.
local function renumber_assistant_boxes(buf)
  local list = {}
  for _, b in ipairs(bubbles[buf] or {}) do
    if is_assistant_style(b.style) then
      list[#list + 1] = b
    end
  end
  table.sort(list, function(a, c)
    return a.start0 < c.start0
  end)
  for i, b in ipairs(list) do
    local s = vim.tbl_extend("force", {}, STYLES.assistant)
    s.label = "#" .. tostring(i)
    b.style = s
    paint_box(b)
  end
end

--- Register a finished range and paint it
local function commit_box(buf, style, start0, end0)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or end0 <= start0 then
    return nil
  end
  local b = { buf = buf, ns = new_ns(), start0 = start0, end0 = end0, style = style }
  push_bubble(buf, b)
  paint_box(b)
  return b
end

--- Finalize a thinking box for fold support (default expanded).
local function attach_thinking_fold(buf, b)
  if not b or not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if b.end0 <= b.start0 then
    return
  end
  b.fold_full = vim.api.nvim_buf_get_lines(buf, b.start0, b.end0, false)
  b.fold_expanded = true
  b.fold_kind = "thinking"
  paint_box(b)
end

--- Box that is still streaming: not registered until it has at least one line
local function open_box(buf, style)
  local n = vim.api.nvim_buf_line_count(buf)
  return { buf = buf, ns = new_ns(), start0 = n, end0 = n, style = style }
end

--- Extend a streaming box to the current end of the buffer
local function grow_box(b)
  if not b or not vim.api.nvim_buf_is_valid(b.buf) then
    return
  end
  local n = vim.api.nvim_buf_line_count(b.buf)
  if n <= b.start0 then
    return
  end
  if b.end0 <= b.start0 then
    push_bubble(b.buf, b)
  end
  b.end0 = n
  paint_box(b)
end

--- Include 1-based line range [first1, last1] in the current tool bubble
local function note_tool_lines(buf, first1, last1)
  if not first1 or first1 < 1 then
    return
  end
  last1 = last1 or first1
  close_thinking_box()
  close_assistant_box()
  local s0, e0 = first1 - 1, last1
  if tool_box and tool_box.buf == buf then
    local b = tool_box.box
    if s0 >= b.start0 and e0 <= b.end0 then
      -- same block rewritten (collapse ×N)
      paint_box(b)
      return
    end
    if b.end0 == s0 then
      -- contiguous next tool block
      b.end0 = e0
      paint_box(b)
      return
    end
  end
  close_tool_batch()
  tool_box = { buf = buf, box = commit_box(buf, STYLES.tool, s0, e0) }
end

--- Redraw every remembered box (VimResized / WinResized repaint).
local function repaint_bubbles(buf)
  for _, b in ipairs(bubbles[buf] or {}) do
    paint_box(b)
  end
end

--- Decorate one appended line with text-level marks (legacy role headers from
--- old sessions, thinking gray italic). Box chrome is painted separately.
local function decorate_line(buf, lnum0, line)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  -- legacy hydrated headers (old sessions)
  if line:match("^### you") then
    in_you_body = true
    in_thinking_body = false
    return
  end
  if line:match("^### assistant") or line:match("^— agent") or line:match("^### error") then
    in_you_body = false
    in_thinking_body = false
    return
  end
  if line:match("^### thinking") then
    in_you_body = false
    in_thinking_body = true
    return
  end
  if line:match("^# pi chat") or line:match("^⚙") then
    in_you_body = false
    in_thinking_body = false
    return
  end
  if not line:match("%S") then
    return
  end
  if in_you_body then
    -- legacy ### you rows: bar as inline virt_text (same column as boxed chrome)
    pcall(vim.api.nvim_buf_set_extmark, buf, role_ns, lnum0, 0, {
      virt_text = { { "▌", "PiYouBar" } },
      virt_text_pos = "inline",
      priority = 10,
    })
  elseif in_thinking_body then
    pcall(vim.api.nvim_buf_set_extmark, buf, role_ns, lnum0, 0, {
      end_col = #line,
      hl_group = "PiThinking",
      hl_eol = true,
    })
  end
end

local function decorate_appended(buf, start_lnum0, lines)
  for i, line in ipairs(lines) do
    decorate_line(buf, start_lnum0 + i - 1, line)
  end
end

local function decorate_range(buf, start0, count)
  if count <= 0 then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, start0, start0 + count, false)
  decorate_appended(buf, start0, lines)
end

--- Configure one chat buffer: nofile, pi-chat filetype (treesitter markdown
--- highlights without host renderers attaching), lock for editing, fallback
--- highlight groups, and the window-resize repaint hook.
function M.setup(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  -- pi-chat (not markdown): keeps TS markdown highlights without host
  -- renderers like render-markdown.nvim attaching and fighting box chrome.
  -- register alone is not enough — nvim-treesitter only auto-starts on
  -- FileType=markdown; start the highlighter explicitly for pi-chat.
  vim.bo[buf].filetype = "pi-chat"
  pcall(vim.treesitter.language.register, "markdown", "pi-chat")
  pcall(vim.treesitter.start, buf, "markdown")
  pcall(function()
    require("render-markdown").buf_disable(buf)
  end)
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  if vim.fn.hlexists("PiYou") == 0 then
    vim.api.nvim_set_hl(0, "PiYou", { fg = 0x7aa2f7, bold = true })
    vim.api.nvim_set_hl(0, "PiYouBar", { fg = 0x7aa2f7 })
    vim.api.nvim_set_hl(0, "PiYouBubble", { bg = 0x2a2a3a, fg = 0xc0caf5 })
    vim.api.nvim_set_hl(0, "PiYouBorder", { fg = 0x7aa2f7, bg = 0x2a2a3a })
    vim.api.nvim_set_hl(0, "PiToolBar", { fg = 0xbb9af7 })
    vim.api.nvim_set_hl(0, "PiToolBubble", { bg = 0x27243a, fg = 0xc0caf5 })
    vim.api.nvim_set_hl(0, "PiToolBorder", { fg = 0xbb9af7, bg = 0x27243a })
    vim.api.nvim_set_hl(0, "PiThinkBar", { fg = 0x565f89 })
    vim.api.nvim_set_hl(0, "PiThinkBubble", { bg = 0x20202c })
    vim.api.nvim_set_hl(0, "PiThinkBorder", { fg = 0x565f89, bg = 0x20202c })
    vim.api.nvim_set_hl(0, "PiAssistant", { fg = 0x9ece6a, bold = true })
    vim.api.nvim_set_hl(0, "PiAsstBar", { fg = 0x9ece6a })
    vim.api.nvim_set_hl(0, "PiAsstBubble", { bg = 0x1f2a1f, fg = 0xc0caf5 })
    vim.api.nvim_set_hl(0, "PiAsstBorder", { fg = 0x9ece6a, bg = 0x1f2a1f })
    vim.api.nvim_set_hl(0, "PiThinking", { fg = 0xa9b1d6, italic = true })
    vim.api.nvim_set_hl(0, "PiAgent", { fg = 0xbb9af7, bold = true })
    vim.api.nvim_set_hl(0, "PiError", { fg = 0xf7768e, bold = true })
    vim.api.nvim_set_hl(0, "PiReview", { fg = 0xe0af68, bold = true })
  end
  vim.api.nvim_create_autocmd("InsertEnter", {
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_get_current_buf() == buf then
          pcall(vim.cmd, "stopinsert")
        end
      end)
    end,
  })
  if not bubble_resize_autocmd then
    bubble_resize_autocmd = vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
      callback = function()
        for b, _ in pairs(bubbles) do
          if vim.api.nvim_buf_is_valid(b) then
            repaint_bubbles(b)
          end
        end
      end,
    })
  end
end

--- Temporarily unlock chat buf for programmatic writes
local function with_write(buf, fn)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local mod = vim.bo[buf].modifiable
  local ro = vim.bo[buf].readonly
  vim.bo[buf].readonly = false
  vim.bo[buf].modifiable = true
  local ok, err = pcall(fn)
  vim.bo[buf].modifiable = mod
  vim.bo[buf].readonly = ro
  -- always re-lock after write
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  if not ok then
    error(err)
  end
end

--- Clear all chat state for `buf` (boxes, decorations, streaming handles) and
--- re-seed the buffer with the "# pi chat" header. Also drops the history
--- cursor so a fresh session does not continue an old transcript.
function M.reset(buf)
  pending = {}
  last_tool = nil
  streaming_assistant = false
  streaming_thinking = false
  follow_scheduled = false
  stick_bottom = true
  suppress_until = 0
  in_you_body = false
  in_thinking_body = false
  tool_box = nil
  think_box = nil
  asst_box = nil
  if buf then
    history_by_buf[buf] = nil
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    for _, b in ipairs(bubbles[buf] or {}) do
      pcall(vim.api.nvim_buf_clear_namespace, buf, b.ns, 0, -1)
    end
    bubbles[buf] = nil
    pcall(vim.api.nvim_buf_clear_namespace, buf, role_ns, 0, -1)
  end
  with_write(buf, function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# pi chat", "" })
  end)
end

function M.stick()
  stick_bottom = true
end

function M.unstick()
  stick_bottom = false
end

--- Scroll chat window to latest content.
--- @param buf integer
--- @param force? boolean
--- @param win? integer explicit chat win (preferred over win_findbuf)
function M.follow(buf, force, win)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if not force and not stick_bottom then
    return
  end
  local last = vim.api.nvim_buf_line_count(buf)
  if last < 1 then
    return
  end
  local target = last
  local probe = vim.api.nvim_buf_get_lines(buf, math.max(0, last - 40), last, false)
  for i = #probe, 1, -1 do
    if probe[i] ~= "" then
      target = last - (#probe - i)
      break
    end
  end

  local wins_list = {}
  if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
    wins_list = { win }
  else
    local ok_ui, ui = pcall(require, "pi.ui")
    if ok_ui and ui.chat_win then
      local w = ui.chat_win()
      if w and vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_buf(w) == buf then
        wins_list = { w }
      end
    end
    if #wins_list == 0 then
      wins_list = vim.fn.win_findbuf(buf) or {}
    end
  end
  if #wins_list == 0 then
    return
  end

  suppress_until = vim.uv.hrtime() + 200e6
  for _, w in ipairs(wins_list) do
    if vim.api.nvim_win_is_valid(w) then
      local height = math.max(1, vim.api.nvim_win_get_height(w))
      local topline = math.max(1, target - height + 1)
      pcall(function()
        vim.wo[w].scrolloff = 0
      end)
      -- Do NOT steal focus from input — only mutate the chat win view
      pcall(vim.api.nvim_win_set_cursor, w, { target, 0 })
      pcall(vim.api.nvim_win_call, w, function()
        vim.fn.winrestview({
          lnum = target,
          col = 0,
          topline = topline,
          leftcol = 0,
          curswant = 0,
        })
      end)
      -- Force GUI/TUI to paint the non-current float
      pcall(vim.api.nvim__redraw, { win = w, cursor = true, valid = true, flush = true })
    end
  end
end

local follow_timer ---@type uv.uv_timer_t|nil
local suspend_follow = false

--- Coalesce rapid stream deltas into one follow-scroll ~per frame (30ms timer).
local function schedule_follow(buf)
  if suspend_follow then
    return
  end
  -- coalesce rapid stream deltas into one scroll ~per frame
  if follow_timer and not follow_timer:is_closing() then
    follow_timer:stop()
    follow_timer:close()
    follow_timer = nil
  end
  follow_scheduled = true
  follow_timer = vim.uv.new_timer()
  follow_timer:start(30, 0, vim.schedule_wrap(function()
    if follow_timer and not follow_timer:is_closing() then
      follow_timer:stop()
      follow_timer:close()
    end
    follow_timer = nil
    follow_scheduled = false
    local win
    pcall(function()
      win = require("pi.ui").chat_win()
    end)
    M.follow(buf, true, win)
  end))
end

--- User scroll tracking + G/gg helpers
function M.attach_scroll(win, buf)
  if scroll_autocmd then
    pcall(vim.api.nvim_del_autocmd, scroll_autocmd)
    scroll_autocmd = nil
  end
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  pcall(function()
    vim.wo[win].scrolloff = 0
  end)
  local last_topline = 0

  scroll_autocmd = vim.api.nvim_create_autocmd("WinScrolled", {
    callback = function(ev)
      if vim.uv.hrtime() < suppress_until then
        return
      end
      if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
        return
      end
      local match = tostring(ev.match or "")
      if match ~= "" and not match:find(tostring(win), 1, true) then
        return
      end
      -- Only unstick when user is focused in chat and scrolls away
      if vim.api.nvim_get_current_win() ~= win then
        return
      end
      local last = vim.api.nvim_buf_line_count(buf)
      local height = math.max(1, vim.api.nvim_win_get_height(win))
      local ok, view = pcall(vim.api.nvim_win_call, win, function()
        return vim.fn.winsaveview()
      end)
      if not ok or type(view) ~= "table" then
        return
      end
      local bottom_visible = (view.topline or 1) + height - 1
      if bottom_visible < last - 1 then
        stick_bottom = false
      else
        stick_bottom = true
      end
      local top = view.topline or 1
      local scrolled_up = last_topline > top
      last_topline = top
      local taller = last > height
      if scrolled_up and top <= 3 and taller and history_by_buf[buf] and not history_loading then
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(win) then
            M.load_older(buf, win)
          end
        end)
      end
    end,
  })

  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "G", function()
    stick_bottom = true
    M.follow(buf, true)
  end, opts)
  vim.keymap.set("n", "gg", function()
    stick_bottom = false
    suppress_until = vim.uv.hrtime() + 100e6
    vim.cmd("normal! gg")
    if history_by_buf[buf] then
      M.load_older(buf, win)
    end
  end, opts)
  local function older_if_short()
    if not history_by_buf[buf] then
      return false
    end
    local height = math.max(1, vim.api.nvim_win_get_height(win))
    local last = vim.api.nvim_buf_line_count(buf)
    local top = vim.fn.line("w0", win)
    if last <= height + 1 or top <= 3 then
      M.load_older(buf, win)
      return true
    end
    return false
  end
  vim.keymap.set("n", "<C-u>", function()
    if older_if_short() then
      return
    end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-u>", true, false, true), "n", false)
  end, opts)
  vim.keymap.set("n", "<ScrollWheelUp>", function()
    if not older_if_short() then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ScrollWheelUp>", true, false, true), "n", false)
    end
  end, opts)
  -- keep chat view read-only: leave insert immediately
  vim.keymap.set("n", "i", "<Nop>", opts)
  vim.keymap.set("n", "a", "<Nop>", opts)
  vim.keymap.set("n", "o", "<Nop>", opts)
  vim.keymap.set("n", "O", "<Nop>", opts)
  vim.keymap.set("n", "c", "<Nop>", opts)
  vim.keymap.set("n", "d", "<Nop>", opts)
  vim.keymap.set("n", "x", "<Nop>", opts)
  vim.keymap.set("n", "r", "<Nop>", opts)
  vim.keymap.set("n", "R", "<Nop>", opts)
  vim.keymap.set("n", "p", "<Nop>", opts)
  vim.keymap.set("n", "P", "<Nop>", opts)
end

--- Append one line to the end of the chat buffer (splits embedded "\n"; resets
--- the tool-collapse chain so any non-tool content breaks a ×N run).
function M.append(buf, line)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  line = line == nil and "" or tostring(line)
  -- nvim_buf_set_lines forbids "\n" inside a single item
  local lines
  if line:find("\n", 1, true) then
    lines = vim.split(line, "\n", { plain = true })
  else
    lines = { line }
  end
  local start0 = vim.api.nvim_buf_line_count(buf)
  with_write(buf, function()
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
  end)
  decorate_appended(buf, start0, lines)
  last_tool = nil
  schedule_follow(buf)
end

--- Max buffer-line width inside a box (inner minus the post-│ space).
local function content_wrap_width(buf, style)
  local inner = bubble_inner_width(buf, style)
  return math.max(8, inner - 1)
end

--- Append one logical line, hard-wrapped to the box content width.
local function append_wrapped_line(buf, line, style, indent)
  local width = content_wrap_width(buf, style)
  for _, w in ipairs(wrap_line(line, width, indent or "")) do
    M.append(buf, w)
  end
end

--- User turn: blue bar + box + light bg (no "you" label)
function M.append_user(buf, text)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  -- separator outside the bubble; commit_box owns chrome
  in_you_body = false
  in_thinking_body = false
  close_tool_batch()
  close_thinking_box()
  close_assistant_box()
  M.append(buf, "")
  local start0 = vim.api.nvim_buf_line_count(buf)
  for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    append_wrapped_line(buf, line, STYLES.user)
  end
  commit_box(buf, STYLES.user, start0, vim.api.nvim_buf_line_count(buf))
end

--- Thinking block: gray text in its own dashed box, no header
function M.append_thinking(buf, text)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  in_you_body = false
  in_thinking_body = true
  close_tool_batch()
  close_thinking_box()
  close_assistant_box()
  M.append(buf, "")
  local start0 = vim.api.nvim_buf_line_count(buf)
  for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    append_wrapped_line(buf, line, STYLES.thinking)
  end
  in_thinking_body = false
  local b = commit_box(buf, STYLES.thinking, start0, vim.api.nvim_buf_line_count(buf))
  attach_thinking_fold(buf, b)
end

local function line_count(buf)
  return vim.api.nvim_buf_line_count(buf)
end

--- Stash the full/collapsed tool payload on the current tool box so
--- toggle_tool_at_cursor can expand/collapse it without re-asking the client.
local function attach_tool_payload(buf, full, expanded, has_err)
  if tool_box and tool_box.buf == buf and tool_box.box then
    local b = tool_box.box
    b.tool_full = full
    b.tool_expanded = expanded and true or false
    b.tool_has_err = has_err and true or false
  end
end

--- Text out of a tool_execution_end result payload
local function result_text(result)
  if type(result) == "string" then
    return result
  end
  if type(result) ~= "table" then
    return ""
  end
  local content = result.content or result.text
  if type(content) == "string" then
    return content
  end
  if type(content) ~= "table" then
    return ""
  end
  local texts = {}
  for _, part in ipairs(content) do
    if type(part) == "string" then
      texts[#texts + 1] = part
    elseif type(part) == "table" and part.text then
      texts[#texts + 1] = tostring(part.text)
    end
  end
  return table.concat(texts, "\n")
end

--- One tool call as a block: header line, argument lines, optional error text
local function tool_block(buf, name, args, ok, count, err)
  local inner = bubble_inner_width(buf, STYLES.tool)
  -- 比 box 内宽再提前 2 格折行：哪怕只超 1 格，linebreak 也会把最后一词
  -- 折到下一行，续行上就看不到右边框了
  local width = math.max(20, inner - 1 - 2)
  return Rtools.tool_block_lines(name, args, ok, count, err, width)
end

local function append_tool_lines(buf, lines)
  local first = line_count(buf) + 1
  for _, l in ipairs(lines) do
    M.append(buf, l)
  end
  note_tool_lines(buf, first, line_count(buf))
  return first
end

--- Paint the error lines of a just-appended block red
local function mark_error_lines(buf, first, n)
  local lines = vim.api.nvim_buf_get_lines(buf, first - 1, first - 1 + n, false)
  for i, l in ipairs(lines) do
    if l:match("^  ! ") then
      pcall(vim.api.nvim_buf_set_extmark, buf, role_ns, first - 1 + i - 1, 0, {
        end_col = #l,
        hl_group = "PiError",
        hl_eol = true,
      })
    end
  end
end

--- Render one finished tool call into the chat, folding identical consecutive
--- calls into the previous block (×N) so a tool loop does not spam the buffer.
local function upsert_tool_end(buf, name, args, ok, err)
  local has_err = err and err ~= ""
  local full = tool_block(buf, name, args, ok, 1, err)
  local key = table.concat(full, "\n")
  -- Collapse identical consecutive calls onto the first block (×N). The key is
  -- the rendered block text, so a wrapping/capping change breaks the chain the
  -- same way a different call would — no stale ×N left on edited lines.
  if
    ok
    and last_tool
    and last_tool.ok
    and last_tool.key == key
    and last_tool.start_line
    and last_tool.start_line + last_tool.n - 1 <= line_count(buf)
  then
    last_tool.count = last_tool.count + 1
    full = tool_block(buf, name, args, ok, last_tool.count, err)
    local expanded = last_tool.expanded ~= false
    local display = collapse_tool_lines(full, expanded, false)
    with_write(buf, function()
      vim.api.nvim_buf_set_lines(buf, last_tool.start_line - 1, last_tool.start_line - 1 + last_tool.n, false, display)
    end)
    last_tool.n = #display
    last_tool.full = full
    note_tool_lines(buf, last_tool.start_line, last_tool.start_line + #display - 1)
    attach_tool_payload(buf, full, expanded, false)
    schedule_follow(buf)
    return
  end
  -- Default expanded (not folded); ftc folds when wanted
  local display = collapse_tool_lines(full, true, has_err)
  local first = append_tool_lines(buf, display)
  last_tool = {
    key = key,
    ok = ok,
    count = 1,
    start_line = first,
    n = #display,
    full = full,
    expanded = true,
  }
  attach_tool_payload(buf, full, true, has_err)
  if has_err then
    mark_error_lines(buf, first, #display)
  end
end

--- `]]` / `[[` navigation between turns. A "turn" is any box start (user, tool,
--- thinking, answer) read from the box registry — never from extmark rows, which
--- drift when a boxed line is rewritten.
function M.jump_message(buf, win, dir)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  win = win or 0
  local cur = vim.api.nvim_win_get_cursor(win)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  --- First line of a painted box (user / tool / thinking) — read from the box
  --- records, not from extmarks, whose rows drift when their line is rewritten
  local function has_box_start(row1)
    for _, b in ipairs(bubbles[buf] or {}) do
      if b.start0 == row1 - 1 and b.end0 > b.start0 then
        return true
      end
    end
    return false
  end
  local function is_turn(i)
    local s = lines[i]
    if not s then
      return false
    end
    if s:match("^### ") or s:match("^— agent") or s:match("^# pi chat") or s:match("^⚙") then
      return true
    end
    return has_box_start(i)
  end
  if dir > 0 then
    for i = cur + 1, #lines do
      if is_turn(i) then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        return
      end
    end
  else
    for i = cur - 1, 1, -1 do
      if is_turn(i) then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        return
      end
    end
  end
end

--- Apply expand/collapse to one foldable box; shifts later boxes by delta.
local function apply_box_expand(buf, target, expanded)
  local full, display
  if target.tool_full then
    full = target.tool_full
    display = collapse_tool_lines(full, expanded, target.tool_has_err)
    if #collapse_tool_lines(full, false, target.tool_has_err) >= #full and not expanded then
      return false
    end
  elseif target.fold_full and target.fold_kind == "thinking" then
    full = target.fold_full
    display = collapse_thinking_lines(full, expanded)
    if #collapse_thinking_lines(full, false) >= #full and not expanded then
      return false
    end
  else
    return false
  end
  local old_end = target.end0
  with_write(buf, function()
    vim.api.nvim_buf_set_lines(buf, target.start0, target.end0, false, display)
  end)
  local new_n = #display
  local delta = new_n - (old_end - target.start0)
  if target.tool_full then
    target.tool_expanded = expanded
  else
    target.fold_expanded = expanded
  end
  target.end0 = target.start0 + new_n
  if delta ~= 0 then
    for _, b in ipairs(bubbles[buf] or {}) do
      if b ~= target and b.start0 >= old_end then
        b.start0 = b.start0 + delta
        b.end0 = b.end0 + delta
      end
    end
    if think_box and think_box.buf == buf and think_box.box and think_box.box ~= target and think_box.box.start0 >= old_end then
      think_box.box.start0 = think_box.box.start0 + delta
      think_box.box.end0 = think_box.box.end0 + delta
    end
    if asst_box and asst_box.buf == buf and asst_box.box.start0 >= old_end then
      asst_box.box.start0 = asst_box.box.start0 + delta
      asst_box.box.end0 = asst_box.box.end0 + delta
    end
    if tool_box and tool_box.buf == buf and tool_box.box and tool_box.box ~= target and tool_box.box.start0 >= old_end then
      tool_box.box.start0 = tool_box.box.start0 + delta
      tool_box.box.end0 = tool_box.box.end0 + delta
    end
    if last_tool and last_tool.start_line then
      local last_start0 = last_tool.start_line - 1
      if last_start0 == target.start0 then
        last_tool.n = new_n
        last_tool.expanded = expanded
        last_tool.full = full
      elseif last_start0 >= old_end then
        last_tool.start_line = last_tool.start_line + delta
      end
    end
  end
  paint_box(target)
  if target.tool_has_err then
    mark_error_lines(buf, target.start0 + 1, new_n)
  end
  return true
end

--- Toggle collapsed/expanded tool box under the cursor. Returns true if handled.
function M.toggle_tool_at_cursor(buf, win)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  win = win or 0
  if type(win) ~= "number" or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local row = vim.api.nvim_win_get_cursor(win)[1] - 1
  local target
  for _, b in ipairs(bubbles[buf] or {}) do
    if
      b.style
      and b.style.bar_hl == "PiToolBar"
      and b.tool_full
      and row >= b.start0
      and row < b.end0
    then
      target = b
      break
    end
  end
  if not target then
    return false
  end
  local preview = collapse_tool_lines(target.tool_full, false, target.tool_has_err)
  if #preview >= #target.tool_full then
    return false
  end
  return apply_box_expand(buf, target, not target.tool_expanded)
end

--- Toggle fold for all toolcall (`ftc`) or thinking (`ftk`) boxes in a buffer.
--- If any of that kind is expanded → fold all; otherwise expand all.
---@param kind "tool"|"thinking"
function M.toggle_fold_kind(buf, kind)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local boxes = {}
  for _, b in ipairs(bubbles[buf] or {}) do
    if kind == "tool" and b.tool_full then
      boxes[#boxes + 1] = b
    elseif kind == "thinking" and b.fold_full and b.fold_kind == "thinking" then
      boxes[#boxes + 1] = b
    end
  end
  if #boxes == 0 then
    return false
  end
  local any_expanded = false
  for _, b in ipairs(boxes) do
    if kind == "tool" and b.tool_expanded then
      any_expanded = true
      break
    end
    if kind == "thinking" and b.fold_expanded then
      any_expanded = true
      break
    end
  end
  local want_expanded = not any_expanded
  table.sort(boxes, function(a, c)
    return a.start0 > c.start0
  end)
  local ok = false
  for _, b in ipairs(boxes) do
    if apply_box_expand(buf, b, want_expanded) then
      ok = true
    end
  end
  return ok
end

--- Open an answer box (#N label) before the first text_delta of a turn.
--- Answers get a full box (not bare text) so their body aligns with toolcall
--- rows; the #N label is assigned at open time, then renumbered on history prepend.
local function ensure_assistant_header(buf)
  if streaming_thinking then
    streaming_thinking = false
    in_thinking_body = false
  end
  close_thinking_box()
  close_tool_batch()
  if streaming_assistant then
    return
  end
  streaming_assistant = true
  last_tool = nil
  in_you_body = false
  in_thinking_body = false
  -- blank separator outside the bubble; box chrome owns the inset
  M.append(buf, "")
  asst_box = { buf = buf, box = open_box(buf, make_assistant_style(buf)) }
end

--- Open the gray dashed thinking box on the first thinking delta of a turn.
local function ensure_thinking_header(buf)
  if streaming_thinking then
    return
  end
  streaming_thinking = true
  streaming_assistant = false
  last_tool = nil
  in_you_body = false
  in_thinking_body = true
  close_tool_batch()
  close_assistant_box()
  M.append(buf, "")
  think_box = { buf = buf, box = open_box(buf, STYLES.thinking) }
end

local function is_structural_line(s)
  return s:match("^—") or s:match("^⚙") or s:match("^###") or s:match("^# pi")
end

--- Append one assistant answer line inside the answer box (no space pad —
--- virt_text `▌│ ` supplies the same left edge as toolcall body text).
local function append_assistant_line(buf, text)
  if text == "" then
    M.append(buf, "")
    return
  end
  -- never hard-wrap table rows — that breaks column alignment
  if is_md_table_row(text) then
    M.append(buf, text)
    with_write(buf, function()
      realign_md_table_at(buf, vim.api.nvim_buf_line_count(buf), "")
    end)
    return
  end
  append_wrapped_line(buf, text, STYLES.assistant)
end

--- Stream one text/thinking delta into the currently open box.
---
--- Deltas arrive as arbitrary chunks: a chunk may continue the last buffer line
--- (merge), start a new one, or contain its own "\n"s. The chunked parse keeps
--- a trailing "\n" as a beginning-of-line flag (`stream_at_bol`) instead of
--- vim.split's phantom final "" row, which used to insert blank lines between
--- markdown table rows. Markdown tables are never hard-wrapped (that breaks
--- column alignment) — they are realigned instead (realign_md_table_at).
local function append_text_delta(buf, delta)
  delta = tostring(delta):gsub("\r\n", "\n"):gsub("\r", "\n")
  local start0 = line_count(buf)
  local extended_last = false
  local is_think = streaming_thinking
  local is_asst = streaming_assistant and not is_think
  local pad = ""
  local wrap_w
  if is_think then
    wrap_w = content_wrap_width(buf, STYLES.thinking)
  elseif is_asst then
    wrap_w = content_wrap_width(buf, STYLES.assistant)
  end

  -- Split into chunks that preserve "\n" as a bol flag instead of vim.split's
  -- trailing "" artifact (which used to insert blank lines between table rows).
  local chunks = {}
  do
    local rest = delta
    while true do
      local idx = rest:find("\n", 1, true)
      if not idx then
        if rest ~= "" then
          chunks[#chunks + 1] = { text = rest, nl = false }
        end
        break
      end
      chunks[#chunks + 1] = { text = rest:sub(1, idx - 1), nl = true }
      rest = rest:sub(idx + 1)
    end
  end

  with_write(buf, function()
    local n = line_count(buf)
    local last = vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1] or ""

    local function write_new(text)
      if text == "" then
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
        return
      end
      if is_asst and is_md_table_row(text) then
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, { text })
        return
      end
      local line = text
      if wrap_w then
        for _, w in ipairs(wrap_line(line, wrap_w, pad)) do
          vim.api.nvim_buf_set_lines(buf, -1, -1, false, { w })
        end
      else
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, { line })
      end
    end

    local function write_merge(text)
      n = line_count(buf)
      last = vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1] or ""
      extended_last = true
      local merged = last .. text
      local body = merged
      if is_asst and is_md_table_row(body) then
        vim.api.nvim_buf_set_lines(buf, n - 1, n, false, { body:gsub("^%s+", "") })
      elseif wrap_w and vim.fn.strdisplaywidth(merged) > wrap_w then
        vim.api.nvim_buf_set_lines(buf, n - 1, n, false, wrap_line(merged, wrap_w, pad))
      else
        vim.api.nvim_buf_set_lines(buf, n - 1, n, false, { merged })
      end
    end

    for _, c in ipairs(chunks) do
      n = line_count(buf)
      last = vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1] or ""
      if c.text ~= "" then
        if stream_at_bol or is_structural_line(last) or last == "" then
          -- non-table text after a table: realign the table above first
          if is_asst and stream_at_bol and not is_md_table_row(c.text) then
            realign_md_table_at(buf, line_count(buf), pad)
          end
          write_new(c.text)
        else
          write_merge(c.text)
        end
        stream_at_bol = false
      elseif c.nl and stream_at_bol then
        -- second newline in a row → blank paragraph; table ended
        if is_asst then
          realign_md_table_at(buf, line_count(buf), pad)
        end
        write_new("")
      end
      if c.nl then
        stream_at_bol = true
        -- Row finished: safe to realign (next chars start a new line).
        if is_asst then
          realign_md_table_at(buf, line_count(buf), pad)
        end
      end
    end
  end)
  local end0 = line_count(buf)
  local from = extended_last and (start0 - 1) or start0
  if from < 0 then
    from = 0
  end
  decorate_range(buf, from, end0 - from)
  last_tool = nil
  if is_asst and asst_box and asst_box.buf == buf then
    grow_box(asst_box.box)
  end
  schedule_follow(buf)
end

--- Agent-session event → chat rendering. The renderer is a pure projection of
--- these events; tools are rendered once on `tool_execution_end` (name + args +
--- error text), assistant text/thinking stream delta-by-delta, and errors surface
--- as red lines (agent_end / message_update error).
function M.on_event(buf, ev)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  if ev.type == "tool_execution_start" then
    local id = ev.toolCallId or ev.id or tostring(vim.uv.hrtime())
    pending[id] = { name = ev.toolName, args = ev.args or ev.input or ev.toolArguments }
    return
  end

  if ev.type == "tool_execution_end" then
    local id = ev.toolCallId or ev.id
    local meta = (id and pending[id]) or { name = ev.toolName }
    if id then
      pending[id] = nil
    end
    local err = ev.isError and result_text(ev.result) or nil
    upsert_tool_end(buf, meta.name or ev.toolName, meta.args, not ev.isError, err)
    return
  end

  if ev.type == "agent_start" then
    streaming_assistant = false
    streaming_thinking = false
    stream_at_bol = false
    in_thinking_body = false
    in_you_body = false
    close_tool_batch()
    close_thinking_box()
    close_assistant_box()
    pending = {}
    stick_bottom = true
    M.append(buf, "")
    return
  end

  if ev.type == "agent_end" then
    streaming_assistant = false
    streaming_thinking = false
    in_thinking_body = false
    close_tool_batch()
    close_thinking_box()
    close_assistant_box()
    last_tool = nil
    -- Surface API / model failures (e.g. 401) that produced no text_delta
    local msgs = ev.messages
    if type(msgs) == "table" then
      for i = #msgs, 1, -1 do
        local raw = msgs[i]
        local m = type(raw) == "table" and (raw.message or raw) or nil
        if type(m) == "table" and m.role == "assistant" then
          if m.stopReason == "error" or (m.errorMessage and m.errorMessage ~= "") then
            local err = m.errorMessage or "assistant stopped with error"
            in_you_body = false
            in_thinking_body = false
            M.append(buf, "")
            local start0 = vim.api.nvim_buf_line_count(buf)
            M.append(buf, tostring(err))
            -- paint error red
            local line = vim.api.nvim_buf_get_lines(buf, start0, start0 + 1, false)[1] or ""
            pcall(vim.api.nvim_buf_set_extmark, buf, role_ns, start0, 0, {
              end_col = #line,
              hl_group = "PiError",
              hl_eol = true,
            })
            vim.schedule(function()
              vim.notify("pi: " .. tostring(err):sub(1, 200), vim.log.levels.ERROR)
            end)
          end
          break
        end
      end
    end
    M.note_pending_review(buf)
    schedule_follow(buf)
    return
  end

  if ev.type == "message_update" and ev.assistantMessageEvent then
    local a = ev.assistantMessageEvent
    local show_think = require("pi.config").opts.show_thinking ~= false
    if a.type == "text_delta" and a.delta then
      ensure_assistant_header(buf)
      append_text_delta(buf, a.delta)
    elseif show_think and (a.type == "thinking_delta" or a.type == "thinking_start") then
      if a.type == "thinking_start" or (a.delta and a.delta ~= "") then
        ensure_thinking_header(buf)
      end
      if a.delta and a.delta ~= "" then
        append_text_delta(buf, a.delta)
        if think_box and think_box.buf == buf then
          grow_box(think_box.box)
        end
      end
    elseif a.type == "thinking_end" then
      streaming_thinking = false
      in_thinking_body = false
      if think_box and think_box.buf == buf and think_box.box then
        grow_box(think_box.box)
        attach_thinking_fold(buf, think_box.box)
      end
      close_thinking_box()
      schedule_follow(buf)
    elseif a.type == "error" then
      local err = a.errorMessage or a.message or a.error or "assistant error"
      in_you_body = false
      in_thinking_body = false
      close_assistant_box()
      M.append(buf, "")
      local start0 = vim.api.nvim_buf_line_count(buf)
      M.append(buf, tostring(err))
      local line = vim.api.nvim_buf_get_lines(buf, start0, start0 + 1, false)[1] or ""
      pcall(vim.api.nvim_buf_set_extmark, buf, role_ns, start0, 0, {
        end_col = #line,
        hl_group = "PiError",
        hl_eol = true,
      })
      streaming_assistant = false
      streaming_thinking = false
      vim.schedule(function()
        vim.notify("pi: " .. tostring(err):sub(1, 200), vim.log.levels.ERROR)
      end)
    elseif a.type == "text_end" or a.type == "done" then
      streaming_assistant = false
      streaming_thinking = false
      in_thinking_body = false
      close_assistant_box()
      schedule_follow(buf)
    end
  end
end

function M._pending_count()
  local n = 0
  for _ in pairs(pending) do
    n = n + 1
  end
  return n
end

function M._last_tool()
  return last_tool
end

--- Extract display text from a message content field
function M.message_text(content)
  if type(content) == "string" then
    return content
  end
  if type(content) ~= "table" then
    return ""
  end
  local texts = {}
  local thinking = {}
  local tools = 0
  local show_think = require("pi.config").opts.show_thinking ~= false
  for _, part in ipairs(content) do
    if type(part) == "string" then
      table.insert(texts, part)
    elseif type(part) == "table" then
      if part.type == "text" and part.text and part.text ~= "" then
        table.insert(texts, part.text)
      elseif show_think and part.type == "thinking" and part.thinking and part.thinking ~= "" then
        table.insert(thinking, part.thinking)
      elseif part.type == "toolCall" then
        tools = tools + 1
      end
    end
  end
  local chunks = {}
  if #thinking > 0 then
    table.insert(chunks, table.concat(thinking, "\n"))
  end
  if #texts > 0 then
    local body = table.concat(texts, "\n")
    if #thinking > 0 then
      table.insert(chunks, body)
    else
      table.insert(chunks, body)
    end
  end
  local out = table.concat(chunks, "\n\n")
  if tools > 0 then
    local line = string.format("⚙ %d tool call(s)", tools)
    out = out ~= "" and (out .. "\n" .. line) or line
  end
  return out
end

--- Split content into thinking / assistant text / tool count (for hydrate paint)
function M.message_parts(content)
  local text = ""
  local thinking = ""
  local tools = 0
  if type(content) == "string" then
    return { text = content, thinking = "", tools = 0, tool_calls = {} }
  end
  if type(content) ~= "table" then
    return { text = "", thinking = "", tools = 0, tool_calls = {} }
  end
  local texts, thinks = {}, {}
  local tool_calls = {}
  local show_think = require("pi.config").opts.show_thinking ~= false
  for _, part in ipairs(content) do
    if type(part) == "string" then
      table.insert(texts, part)
    elseif type(part) == "table" then
      if part.type == "text" and part.text and part.text ~= "" then
        table.insert(texts, part.text)
      elseif show_think and part.type == "thinking" and part.thinking and part.thinking ~= "" then
        table.insert(thinks, part.thinking)
      elseif part.type == "toolCall" then
        tool_calls[#tool_calls + 1] = { name = part.name, args = part.arguments or part.args }
      end
    end
  end
  return {
    text = table.concat(texts, "\n"),
    thinking = table.concat(thinks, "\n"),
    tools = #tool_calls,
    tool_calls = tool_calls,
  }
end

--- Normalize get_messages payload → list of {role, content}
function M.normalize_messages(data)
  if type(data) ~= "table" then
    return {}
  end
  local list = data.messages or data
  if type(list) ~= "table" then
    return {}
  end
  -- single message object?
  if list.role or list.message then
    list = { list }
  end
  local out = {}
  for _, msg in ipairs(list) do
    if type(msg) == "table" then
      local role = msg.role
      local content = msg.content
      if msg.message and type(msg.message) == "table" then
        role = role or msg.message.role
        content = content or msg.message.content
      end
      if role == "user" or role == "assistant" then
        table.insert(out, { role = role, content = content })
      end
    end
  end
  return out
end

--- Rebuild chat buffer from historical messages (skip toolResult spam)
local function paint_messages(buf, messages)
  local count = 0
  for _, msg in ipairs(messages or {}) do
    local parts = M.message_parts(msg.content)
    local has = (parts.text and parts.text:match("%S"))
      or (parts.thinking and parts.thinking:match("%S"))
      or (parts.tools and parts.tools > 0)
    if has then
      if msg.role == "user" then
        M.append_user(buf, parts.text ~= "" and parts.text or M.message_text(msg.content))
      else
        if parts.thinking and parts.thinking:match("%S") then
          M.append_thinking(buf, parts.thinking)
        end
        if parts.text and parts.text:match("%S") then
          in_you_body = false
          in_thinking_body = false
          M.append(buf, "")
          local start0 = vim.api.nvim_buf_line_count(buf)
          for line in (parts.text .. "\n"):gmatch("(.-)\n") do
            append_assistant_line(buf, line)
          end
          commit_box(buf, make_assistant_style(buf), start0, vim.api.nvim_buf_line_count(buf))
        end
        if parts.tool_calls and #parts.tool_calls > 0 then
          for _, call in ipairs(parts.tool_calls) do
            local full = tool_block(buf, call.name, call.args, nil, 1)
            local display = collapse_tool_lines(full, true, false)
            append_tool_lines(buf, display)
            attach_tool_payload(buf, full, false, false)
          end
        elseif parts.tools and parts.tools > 0 then
          append_tool_lines(buf, { string.format("⚙ %d tool call(s)", parts.tools) })
        end
      end
      M.append(buf, "")
      count = count + 1
    end
  end
  return count
end

--- Move every box/streaming-handle at or after `at` (0-based) by `delta` lines,
--- keeping the registry in sync when lines are inserted/removed above them
--- (history prepend, tool expand/collapse).
local function shift_bubbles(buf, at, delta)
  if not delta or delta == 0 then
    return
  end
  for _, b in ipairs(bubbles[buf] or {}) do
    if b.start0 >= at then
      b.start0 = b.start0 + delta
      b.end0 = b.end0 + delta
    end
  end
  if tool_box and tool_box.buf == buf and tool_box.box.start0 >= at then
    tool_box.box.start0 = tool_box.box.start0 + delta
    tool_box.box.end0 = tool_box.box.end0 + delta
  end
  if think_box and think_box.buf == buf and think_box.box.start0 >= at then
    think_box.box.start0 = think_box.box.start0 + delta
    think_box.box.end0 = think_box.box.end0 + delta
  end
  if asst_box and asst_box.buf == buf and asst_box.box.start0 >= at then
    asst_box.box.start0 = asst_box.box.start0 + delta
    asst_box.box.end0 = asst_box.box.end0 + delta
  end
end

--- Insert the previous page above the current transcript. Keeps the viewport
--- on the same lines unless the user is already at the top.
function M.load_older(buf, win)
  local st = history_by_buf[buf]
  if history_loading or not st or (st.cursor or 0) <= 0 then
    return false
  end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  history_loading = true
  local msgs, exhausted
  for _ = 1, 8 do
    msgs, exhausted = require("pi.sessions").history_page(st)
    if #msgs > 0 or exhausted or (st.cursor or 0) <= 0 then
      break
    end
  end
  if exhausted or (st.cursor or 0) <= 0 then
    history_by_buf[buf] = nil
  end
  if #msgs == 0 then
    history_loading = false
    return false
  end
  -- paint into a scratch buffer so the live transcript state (streaming boxes,
  -- pending tools, collapse chain) is untouched; the boxes are re-homed below
  local saved = {
    pending = pending,
    last_tool = last_tool,
    streaming_assistant = streaming_assistant,
    streaming_thinking = streaming_thinking,
    follow_scheduled = follow_scheduled,
    stick_bottom = stick_bottom,
    suppress_until = suppress_until,
    in_you_body = in_you_body,
    in_thinking_body = in_thinking_body,
    tool_box = tool_box,
    think_box = think_box,
    asst_box = asst_box,
  }
  local tmp = vim.api.nvim_create_buf(false, true)
  suspend_follow = true
  local painted_ok, painted_err = pcall(function()
    M.setup(tmp)
    M.reset(tmp)
    paint_messages(tmp, msgs)
  end)
  pending = saved.pending
  last_tool = saved.last_tool
  streaming_assistant = saved.streaming_assistant
  streaming_thinking = saved.streaming_thinking
  follow_scheduled = saved.follow_scheduled
  stick_bottom = saved.stick_bottom
  suppress_until = saved.suppress_until
  in_you_body = saved.in_you_body
  in_thinking_body = saved.in_thinking_body
  tool_box = saved.tool_box
  think_box = saved.think_box
  asst_box = saved.asst_box
  suspend_follow = false
  if not painted_ok then
    history_loading = false
    pcall(vim.api.nvim_buf_delete, tmp, { force = true })
    error(painted_err)
  end
  local new_lines = vim.api.nvim_buf_get_lines(tmp, 2, -1, false)
  local added = #new_lines
  if added == 0 then
    history_loading = false
    bubbles[tmp] = nil
    pcall(vim.api.nvim_buf_delete, tmp, { force = true })
    return false
  end
  local insert_at = 2
  local mark = vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1]
  if mark == OLDER_MARK then
    insert_at = 3
  end
  local view
  if win and vim.api.nvim_win_is_valid(win) then
    local ok, saved = pcall(vim.api.nvim_win_call, win, function()
      return vim.fn.winsaveview()
    end)
    if ok then
      view = saved
    end
  end
  with_write(buf, function()
    vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, new_lines)
  end)
  local coord_delta = insert_at - 2
  shift_bubbles(buf, insert_at, added)
  for _, b in ipairs(bubbles[tmp] or {}) do
    b.buf = buf
    b.ns = new_ns()
    b.start0 = b.start0 + coord_delta
    b.end0 = b.end0 + coord_delta
    push_bubble(buf, b)
    paint_box(b)
  end
  bubbles[tmp] = nil
  pcall(vim.api.nvim_buf_delete, tmp, { force = true })
  renumber_assistant_boxes(buf)
  if not history_by_buf[buf] and vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1] == OLDER_MARK then
    with_write(buf, function()
      vim.api.nvim_buf_set_lines(buf, 2, 3, false, {})
    end)
    shift_bubbles(buf, 3, -1)
    added = added - 1
  end
  if view and win and vim.api.nvim_win_is_valid(win) then
    if (view.topline or 1) > 3 then
      view.topline = view.topline + added
      view.lnum = (view.lnum or 1) + added
    else
      view.topline = 4
      view.lnum = 4
    end
    suppress_until = vim.uv.hrtime() + 200e6
    pcall(vim.api.nvim_win_call, win, function()
      vim.fn.winrestview(view)
    end)
  end
  history_loading = false
  M.unstick()
  return true
end

--- Paint the initial/resumed transcript (hydrate) into `buf`. History support
--- records the paging cursor in history_by_buf so gg / scroll-to-top can fetch
--- older turns later.
function M.hydrate(buf, messages, opts)
  opts = opts or {}
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return 0
  end
  M.reset(buf)
  history_by_buf[buf] = opts.history
  if opts.history then
    M.append(buf, OLDER_MARK)
  end
  local count = paint_messages(buf, messages)
  if opts.footer ~= false then
    M.append(buf, opts.footer or "· resumed session")
  end
  stick_bottom = true
  schedule_follow(buf)
  return count
end

local REVIEW_HINT_RE = "^◎ %d+ files? pending review"

--- After agent_end: remind if host-tool edits are waiting for Accept/Reject.
function M.note_pending_review(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local n = 0
  pcall(function()
    n = #require("pi.session").touched()
  end)
  local line
  if n <= 0 then
    line = nil
  elseif n == 1 then
    line = "◎ 1 file pending review · :PiDiff"
  else
    line = string.format("◎ %d files pending review · :PiDiff", n)
  end
  local last = vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] or ""
  local prev_is_hint = last:match(REVIEW_HINT_RE) ~= nil
  if not line then
    if prev_is_hint then
      with_write(buf, function()
        vim.api.nvim_buf_set_lines(buf, -2, -1, false, {})
      end)
    end
    pcall(function()
      require("pi.statusline").repaint()
    end)
    return
  end
  if prev_is_hint then
    with_write(buf, function()
      vim.api.nvim_buf_set_lines(buf, -2, -1, false, { line })
    end)
  else
    M.append(buf, "")
    local start0 = vim.api.nvim_buf_line_count(buf)
    M.append(buf, line)
    local painted = vim.api.nvim_buf_get_lines(buf, start0, start0 + 1, false)[1] or line
    pcall(vim.api.nvim_buf_set_extmark, buf, role_ns, start0, 0, {
      end_col = #painted,
      hl_group = "PiReview",
      hl_eol = true,
    })
  end
  pcall(function()
    require("pi.statusline").repaint()
  end)
end

return M
