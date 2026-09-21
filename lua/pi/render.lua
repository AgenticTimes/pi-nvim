-- Chat buffer rendering: compact tool lines, collapse repeats, stream assistant text
local M = {}

-- pending tools by toolCallId → { name, detail, line }
local pending = {}
-- last compact tool summary for collapse: { name, detail, count, line_idx }
local last_tool = nil
local streaming_assistant = false
local streaming_thinking = false
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
}

--- bufnr → { { buf, ns, start0, end0, style }, ... } end0 exclusive
local bubbles = {}
--- boxes still being streamed: { buf, box }
local tool_box = nil
local think_box = nil
local box_seq = 0
local bubble_resize_autocmd ---@type integer|nil

--- Each box owns an extmark namespace so a repaint is "wipe the namespace, redraw".
--- Range-scoped clears are unreliable here: virt_lines + nvim_buf_set_lines shifts
--- the stored row of the edited line, so a stale mark survives the clear.
local function new_ns()
  box_seq = box_seq + 1
  return vim.api.nvim_create_namespace("pi_box_" .. box_seq)
end

local function bubble_inner_width(buf)
  local wins = vim.fn.win_findbuf(buf)
  local avail
  if wins[1] then
    local info = vim.fn.getwininfo(wins[1])[1]
    if info then
      avail = info.width - (info.textoff or 0)
    else
      avail = vim.api.nvim_win_get_width(wins[1])
    end
  else
    avail = vim.o.columns
  end
  -- leave 2 cells for left/right │
  return math.max(10, avail - 2)
end

local function push_bubble(buf, b)
  local list = bubbles[buf]
  if not list then
    list = {}
    bubbles[buf] = list
  end
  list[#list + 1] = b
end

--- Top rule with the role label tucked into its left corner:
--- `╭─ user ───────╮` / `╭┄ thinking ┄┄┄╮` / `┌─ toolcall ───┐`
local function top_rule(style, inner)
  local label = style.label
  if not label or label == "" then
    return { { style.tl .. string.rep(style.h, inner) .. style.tr, style.border_hl } }
  end
  local head = style.h .. " "
  local tail = " "
  local used = vim.fn.strdisplaywidth(head .. label .. tail)
  if used >= inner then
    return { { style.tl .. string.rep(style.h, inner) .. style.tr, style.border_hl } }
  end
  return {
    { style.tl .. head, style.border_hl },
    { label, style.label_hl },
    { tail .. string.rep(style.h, inner - used) .. style.tr, style.border_hl },
  }
end

--- Paint one boxed row: left bar + bg + side borders + top/bottom rule
local function paint_row(buf, ns, row, line, style, inner, is_first, is_last)
  local content_w = vim.fn.strdisplaywidth(line)
  -- "│ " eats one inner cell (the space after │)
  local pad = math.max(0, inner - 1 - content_w)
  -- body: bar + bg + left border
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
    sign_text = style.bar,
    sign_hl_group = style.bar_hl,
    line_hl_group = style.body_hl,
    virt_text = { { style.v .. " ", style.border_hl } },
    virt_text_pos = "inline",
    priority = 10,
  })
  -- right border (padded to inner width)
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
    virt_text = { { string.rep(" ", pad) .. style.v, style.border_hl } },
    virt_text_pos = "eol",
    priority = 11,
  })
  -- top rule (virt_lines_above is a boolean on this nvim)
  if is_first then
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
      virt_lines = { top_rule(style, inner) },
      virt_lines_above = true,
      priority = 12,
    })
  end
  -- bottom rule
  if is_last then
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
      virt_lines = { { { style.bl .. string.rep(style.h, inner) .. style.br, style.border_hl } } },
      virt_lines_above = false,
      priority = 12,
    })
  end
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
  local inner = bubble_inner_width(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, b.start0, b.end0, false)
  for i, line in ipairs(lines) do
    local row = b.start0 + i - 1
    paint_row(buf, b.ns, row, line, b.style, inner, row == b.start0, i == #lines)
  end
end

local function close_tool_batch()
  tool_box = nil
end

local function close_thinking_box()
  think_box = nil
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

local function repaint_bubbles(buf)
  for _, b in ipairs(bubbles[buf] or {}) do
    paint_box(b)
  end
end

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
    pcall(vim.api.nvim_buf_set_extmark, buf, role_ns, lnum0, 0, {
      sign_text = "▌",
      sign_hl_group = "PiYouBar",
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

function M.setup(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "markdown"
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
    vim.api.nvim_set_hl(0, "PiThinking", { fg = 0xa9b1d6, italic = true })
    vim.api.nvim_set_hl(0, "PiAgent", { fg = 0xbb9af7, bold = true })
    vim.api.nvim_set_hl(0, "PiError", { fg = 0xf7768e, bold = true })
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
  M.append(buf, "")
  local start0 = vim.api.nvim_buf_line_count(buf)
  for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    M.append(buf, line)
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
  M.append(buf, "")
  local start0 = vim.api.nvim_buf_line_count(buf)
  for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    M.append(buf, line)
  end
  in_thinking_body = false
  commit_box(buf, STYLES.thinking, start0, vim.api.nvim_buf_line_count(buf))
end

local function line_count(buf)
  return vim.api.nvim_buf_line_count(buf)
end

local function short_name(name)
  name = tostring(name or "?")
  return name:gsub("^nvim_", "")
end

--- Cap a rendered block, keeping the head and counting what was dropped
local function cap_lines(lines, max)
  if #lines <= max then
    return lines
  end
  local out = {}
  for i = 1, max - 1 do
    out[i] = lines[i]
  end
  out[max] = string.format("… +%d lines", #lines - max + 1)
  return out
end

--- Guard rail against a tool argument carrying a whole file (write/edit)
local MAX_ARG_CHARS = 2000

local function clip(text)
  if vim.fn.strchars(text) <= MAX_ARG_CHARS then
    return text
  end
  return vim.fn.strcharpart(text, 0, MAX_ARG_CHARS) .. " …"
end

--- The arguments a tool was actually called with. This is the part that used to
--- be missing: only a one-line path/command summary was rendered before.
local function tool_arg_lines(args)
  local out = {}
  if type(args) ~= "table" then
    return out
  end
  local function push(prefix, value)
    local parts = vim.split(clip(tostring(value)), "\n", { plain = true })
    out[#out + 1] = prefix .. parts[1]
    for i = 2, #parts do
      out[#out + 1] = "  " .. parts[i]
    end
  end
  if args.command ~= nil then
    push("$ ", args.command)
  end
  local keys = {}
  for k in pairs(args) do
    if k ~= "command" then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = args[k]
    if type(v) == "table" then
      v = vim.json.encode(v)
    end
    if v ~= nil and tostring(v) ~= "" then
      push(tostring(k) .. ": ", v)
    end
  end
  return cap_lines(out, 12)
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

--- Hard-wrap a line to `width` display cells. nvim cannot put virt_text on the
--- wrapped segments of a buffer line, so a too-long line escapes the box border.
local function wrap_line(text, width, indent)
  if width < 8 or vim.fn.strdisplaywidth(text) <= width then
    return { text }
  end
  local out = {}
  local rest = text
  while vim.fn.strdisplaywidth(rest) > width do
    local i = vim.fn.strchars(rest)
    while i > 1 and vim.fn.strdisplaywidth(vim.fn.strcharpart(rest, 0, i)) > width do
      i = i - 1
    end
    out[#out + 1] = vim.fn.strcharpart(rest, 0, i)
    rest = indent .. vim.fn.strcharpart(rest, i)
  end
  out[#out + 1] = rest
  return out
end

--- One tool call as a block: header line, argument lines, optional error text
local function tool_block(buf, name, args, ok, count, err)
  local mark = ok == nil and "…" or (ok and "✓" or "✗")
  local head = string.format("⚙ %s %s", short_name(name), mark)
  if count and count > 1 then
    head = head .. string.format(" ×%d", count)
  end
  local raw = { head }
  for _, l in ipairs(tool_arg_lines(args)) do
    raw[#raw + 1] = "  " .. l
  end
  if err and err ~= "" then
    for _, l in ipairs(cap_lines(vim.split(err, "\n", { plain = true }), 6)) do
      raw[#raw + 1] = "  ! " .. l
    end
  end
  local width = math.max(20, bubble_inner_width(buf) - 1)
  local lines = {}
  for _, l in ipairs(raw) do
    for _, w in ipairs(wrap_line(l, width, "  ")) do
      lines[#lines + 1] = w
    end
  end
  -- wrapping can multiply lines: keep one tool call bounded on screen
  return cap_lines(lines, 24)
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

local function upsert_tool_end(buf, name, args, ok, err)
  local lines = tool_block(buf, name, args, ok, 1, err)
  local key = table.concat(lines, "\n")
  -- identical consecutive calls collapse onto the first block (×N)
  if
    ok
    and last_tool
    and last_tool.ok
    and last_tool.key == key
    and last_tool.start_line
    and last_tool.start_line + last_tool.n - 1 <= line_count(buf)
  then
    last_tool.count = last_tool.count + 1
    local updated = tool_block(buf, name, args, ok, last_tool.count, err)
    with_write(buf, function()
      vim.api.nvim_buf_set_lines(buf, last_tool.start_line - 1, last_tool.start_line - 1 + last_tool.n, false, updated)
    end)
    last_tool.n = #updated
    note_tool_lines(buf, last_tool.start_line, last_tool.start_line + #updated - 1)
    schedule_follow(buf)
    return
  end
  local first = append_tool_lines(buf, lines)
  last_tool = { key = key, ok = ok, count = 1, start_line = first, n = #lines }
  if err and err ~= "" then
    mark_error_lines(buf, first, #lines)
  end
end

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
  -- blank separator only (no "assistant" / "agent" label)
  M.append(buf, "")
end

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
  M.append(buf, "")
  think_box = { buf = buf, box = open_box(buf, STYLES.thinking) }
end

local function is_structural_line(s)
  return s:match("^—") or s:match("^⚙") or s:match("^###") or s:match("^# pi")
end

local function append_text_delta(buf, delta)
  delta = tostring(delta):gsub("\r\n", "\n"):gsub("\r", "\n")
  local parts = vim.split(delta, "\n", { plain = true })
  local start0 = line_count(buf)
  -- if appending after structural line, new lines start at start0; else may extend last line
  local extended_last = false
  with_write(buf, function()
    local n = line_count(buf)
    local last = vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1] or ""

    local function push_line(text)
      n = line_count(buf)
      last = vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1] or ""
      if text == "" and last == "" then
        return
      end
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { text })
    end

    if is_structural_line(last) or last == "" then
      push_line(parts[1])
    else
      extended_last = true
      vim.api.nvim_buf_set_lines(buf, n - 1, n, false, { last .. (parts[1] or "") })
    end

    for i = 2, #parts do
      push_line(parts[i])
    end
  end)
  local end0 = line_count(buf)
  local from = extended_last and (start0 - 1) or start0
  if from < 0 then
    from = 0
  end
  decorate_range(buf, from, end0 - from)
  last_tool = nil
  schedule_follow(buf)
end

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
    in_thinking_body = false
    in_you_body = false
    close_tool_batch()
    close_thinking_box()
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
      close_thinking_box()
      schedule_follow(buf)
    elseif a.type == "error" then
      local err = a.errorMessage or a.message or a.error or "assistant error"
      in_you_body = false
      in_thinking_body = false
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
          for line in (parts.text .. "\n"):gmatch("(.-)\n") do
            M.append(buf, line)
          end
        end
        if parts.tool_calls and #parts.tool_calls > 0 then
          for _, call in ipairs(parts.tool_calls) do
            append_tool_lines(buf, tool_block(buf, call.name, call.args, nil, 1))
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

return M
