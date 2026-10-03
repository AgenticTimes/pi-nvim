local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.render"] = nil
local render = require("pi.render")
local b = vim.api.nvim_create_buf(false, true)
render.setup(b)
h.assert_eq(vim.bo[b].filetype, "pi-chat", "chat ft isolates from markdown renderers")
-- When markdown parser is installed, highlighter must be attached (register alone is not enough).
do
  local ok_add = pcall(vim.treesitter.language.add, "markdown")
  if ok_add then
    local has = false
    pcall(function()
      has = vim.treesitter.highlighter.active[b] ~= nil
    end)
    h.assert_truthy(has, "treesitter highlighter active on pi-chat")
  end
end
render.reset(b)

-- 5 identical successful reads → one bubble with ×5 on the chrome
for i = 1, 5 do
  local id = "c" .. i
  render.on_event(b, {
    type = "tool_execution_start",
    toolCallId = id,
    toolName = "nvim_read_buffer",
    args = { path = "demo/sample.lua" },
  })
  render.on_event(b, {
    type = "tool_execution_end",
    toolCallId = id,
    toolName = "nvim_read_buffer",
    isError = false,
  })
end

local function chrome_labels(buf)
  local labels = {}
  for _, box_ns in ipairs({ h.last_box_ns(buf) }) do
    for _, m in ipairs(h.box_marks(buf, box_ns)) do
      local d = m[4] or {}
      if d.virt_lines_above and d.virt_lines then
        local top = ""
        for _, chunk in ipairs(d.virt_lines[1] or {}) do
          top = top .. (chunk[1] or "")
        end
        if top ~= "" then
          labels[#labels + 1] = top
        end
      end
    end
  end
  -- All tool boxes on buf
  for name, id in pairs(vim.api.nvim_get_namespaces()) do
    if tostring(name):find("^pi_box_", 1) then
      for _, m in ipairs(h.box_marks(buf, id)) do
        local d = m[4] or {}
        if d.virt_lines_above and d.virt_lines then
          local top = ""
          for _, chunk in ipairs(d.virt_lines[1] or {}) do
            top = top .. (chunk[1] or "")
          end
          if top:find("sample", 1, true) or top:find("read", 1, true) or top:find("%$", 1) or top:find("bash", 1, true) or top:find("other", 1, true) then
            local seen = false
            for _, t in ipairs(labels) do
              if t == top then
                seen = true
                break
              end
            end
            if not seen then
              labels[#labels + 1] = top
            end
          end
        end
      end
    end
  end
  return labels
end

local labels = chrome_labels(b)
local joined = table.concat(labels, " | ")
h.assert_truthy(joined:find("×5", 1, true), "chrome has ×5: " .. joined)
h.assert_truthy(joined:find("sample", 1, true) or joined:find("read", 1, true), "chrome has read path: " .. joined)

-- different path breaks collapse
render.on_event(b, {
  type = "tool_execution_start",
  toolCallId = "d1",
  toolName = "nvim_read_buffer",
  args = { path = "other.lua" },
})
render.on_event(b, {
  type = "tool_execution_end",
  toolCallId = "d1",
  toolName = "nvim_read_buffer",
  isError = false,
})
labels = chrome_labels(b)
joined = table.concat(labels, " | ")
h.assert_truthy(joined:find("other", 1, true), "second path new chrome: " .. joined)
h.assert_truthy(joined:find("×5", 1, true), "first ×5 kept: " .. joined)

-- tool call summaries live on the chrome (top rule), not ⚙ body headers
local tb = vim.api.nvim_create_buf(false, true)
render.setup(tb)
render.reset(tb)
render.on_event(tb, { type = "tool_execution_start", toolCallId = "r1", toolName = "nvim_read_buffer", args = { path = "demo/sample.lua", offset = 10, limit = 20 } })
render.on_event(tb, { type = "tool_execution_end", toolCallId = "r1", toolName = "nvim_read_buffer", isError = false })
render.on_event(tb, { type = "tool_execution_start", toolCallId = "s1", toolName = "bash", args = { command = "git status --short" } })
render.on_event(tb, { type = "tool_execution_end", toolCallId = "s1", toolName = "bash", isError = false })
render.on_event(tb, { type = "tool_execution_start", toolCallId = "e1", toolName = "bash", args = { command = "nope" } })
render.on_event(tb, {
  type = "tool_execution_end",
  toolCallId = "e1",
  toolName = "bash",
  isError = true,
  result = { content = { { type = "text", text = "command not found" } } },
})
-- successful tools stay open until agent_end, then auto-fold
render.on_event(tb, { type = "agent_end" })
local tjoin = table.concat(vim.api.nvim_buf_get_lines(tb, 0, -1, false), "\n")
local tl = table.concat(chrome_labels(tb), " | ")
h.assert_truthy(tl:find("sample", 1, true) or tl:find("read", 1, true), "read chrome: " .. tl)
h.assert_truthy(tl:find("git status", 1, true) or tl:find("%$ git", 1), "bash chrome: " .. tl)
h.assert_truthy(tjoin:find("ftt to expand", 1, true) or tl:find("ftt", 1, true), "auto-folded success tools")
-- remaining args (offset/limit) may stay as folded preview; path is on chrome
h.assert_truthy(tjoin:find("limit:", 1, true) or tjoin:find("offset:", 1, true) or tl:find("sample", 1, true), "preview or chrome has detail")
-- errors stay expanded
h.assert_truthy(tjoin:find("  ! command not found", 1, true), "tool error text")
h.assert_truthy(tl:find("✗", 1, true) or tjoin:find("✗", 1, true), "failure mark on chrome/body: " .. tl)
-- the three tool calls form one contiguous box
local tool_boxes = 0
for _, b in ipairs(vim.api.nvim_buf_get_extmarks(tb, h.last_box_ns(tb), 0, -1, { details = true })) do
  if (b[4] or {}).virt_lines then
    tool_boxes = tool_boxes + 1
  end
end
h.assert_eq(tool_boxes, 2, "one top + one bottom rule for the whole batch")

-- long tool args collapse; toggle expands / collapses
local lb = vim.api.nvim_create_buf(false, true)
render.setup(lb)
render.reset(lb)
local long_cmd = table.concat({
  "line1",
  "line2",
  "line3",
  "line4",
  "line5",
  "line6",
  "line7",
}, "\n")
render.on_event(lb, {
  type = "tool_execution_start",
  toolCallId = "long1",
  toolName = "bash",
  args = { command = long_cmd },
})
render.on_event(lb, {
  type = "tool_execution_end",
  toolCallId = "long1",
  toolName = "bash",
  isError = false,
})
render.on_event(lb, { type = "agent_end" })
local ljoin = table.concat(vim.api.nvim_buf_get_lines(lb, 0, -1, false), "\n")
h.assert_truthy(ljoin:find("ftt to expand", 1, true), "auto-folded after agent_end: " .. ljoin)
h.assert_false(ljoin:find("line7", 1, true), "tail hidden while auto-folded")
-- Expand/collapse via fold-kind (cursor-based toggle needs a tool row under the
-- cursor; chrome-summary layouts vary by prior suite windows).
h.assert_truthy(render.toggle_fold_kind(lb, "tool"), "ftt expands all tools")
ljoin = table.concat(vim.api.nvim_buf_get_lines(lb, 0, -1, false), "\n")
h.assert_truthy(ljoin:find("line7", 1, true), "tail visible when expanded: " .. ljoin)
h.assert_truthy(render.toggle_fold_kind(lb, "tool"), "ftt folds all tools")
ljoin = table.concat(vim.api.nvim_buf_get_lines(lb, 0, -1, false), "\n")
h.assert_truthy(ljoin:find("ftt to expand", 1, true), "collapse marker ftt to expand: " .. ljoin)
h.assert_false(ljoin:find("line7", 1, true), "tail hidden while collapsed")

-- assistant text has no role header (OpenCode-style)
render.on_event(b, { type = "agent_start" })
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "text_delta", delta = "Hello" },
})
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "text_delta", delta = " world" },
})
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
local joined = table.concat(lines, "\n")
h.assert_false(joined:find("### assistant", 1, true), "no assistant header")
h.assert_false(joined:find("— agent —", 1, true), "no agent rule")
h.assert_truthy(joined:find("Hello world", 1, true), "streamed text")

-- newlines in deltas become real buffer lines
render.on_event(b, { type = "agent_start" })
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "text_delta", delta = "## Title\n\n- item1\n- item2" },
})
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "text_delta", delta = "\n\nmore" },
})
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
-- find last assistant block (box virt_text insets; buffer text has no space pad)
local saw_title, saw_item, saw_more = false, false, false
for _, l in ipairs(lines) do
  if l == "## Title" then
    saw_title = true
  end
  if l == "- item1" then
    saw_item = true
  end
  if l == "more" then
    saw_more = true
  end
end
h.assert_truthy(saw_title, "title on own line")
h.assert_truthy(saw_item, "list item on own line")
h.assert_truthy(saw_more, "continued after newline")

-- follow moves cursor to last line when stick is on
local win = vim.api.nvim_open_win(b, false, {
  relative = "editor",
  width = 40,
  height = 8,
  row = 1,
  col = 1,
  style = "minimal",
})
-- match chat float: bar lives in virt_text, not a sign gutter
vim.wo[win].signcolumn = "no"
vim.api.nvim_win_set_cursor(win, { 1, 0 })
local tmp = vim.api.nvim_create_buf(false, true)
local other = vim.api.nvim_open_win(tmp, true, {
  relative = "editor",
  width = 10,
  height = 5,
  row = 12,
  col = 1,
  style = "minimal",
})
render.stick()
local chat_win = win
render.follow(b, true, chat_win)
local last_line = vim.api.nvim_buf_line_count(b)
local content_line = last_line
local lines_tail = vim.api.nvim_buf_get_lines(b, math.max(0, last_line - 5), last_line, false)
local te = 0
for i = #lines_tail, 1, -1 do
  if lines_tail[i] == "" then
    te = te + 1
  else
    break
  end
end
h.assert_truthy(te >= 2, "buffer keeps ≥2 trailing blank lines: " .. te)
content_line = last_line - te
h.assert_eq(vim.api.nvim_win_get_cursor(win)[1], math.min(last_line, content_line + 1), "cursor on first pad line")
local view = vim.api.nvim_win_call(win, function()
  return vim.fn.winsaveview()
end)
-- height=8, pad=2 → topline = content - 8 + 1 + 2 = content - 5
h.assert_eq(view.topline, math.max(1, content_line - 5), "follow leaves 2 blank rows at bottom")

render.unstick()
vim.api.nvim_win_set_cursor(win, { 2, 0 })
render.follow(b, false, chat_win)
h.assert_eq(vim.api.nvim_win_get_cursor(win)[1], 2, "unstick + follow(false) keeps cursor")
render.follow(b, true, chat_win)
h.assert_eq(vim.api.nvim_win_get_cursor(win)[1], math.min(last_line, content_line + 1), "force follows to pad")

-- multiline append must not error (nvim forbids \\n in a single set_lines item)
-- Inserts before the 2-line bottom pad, so slice from content_end.
local before = math.max(0, vim.api.nvim_buf_line_count(b) - 2)
render.append(b, "line-a\nline-b\nline-c")
local after = vim.api.nvim_buf_get_lines(b, before, -1, false)
h.assert_eq(after[1], "line-a", "a")
h.assert_eq(after[2], "line-b", "b")
h.assert_eq(after[3], "line-c", "c")
h.assert_eq(after[4], "", "pad1")
h.assert_eq(after[5], "", "pad2")

-- API errors surface in chat (previously looked like silent no-response)
render.on_event(b, { type = "agent_start" })
render.on_event(b, {
  type = "agent_end",
  messages = {
    {
      role = "assistant",
      content = {},
      stopReason = "error",
      errorMessage = "OpenAI API error (401): Incorrect API key",
    },
  },
})
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
joined = table.concat(lines, "\n")
h.assert_false(joined:find("### error", 1, true), "no error header")
h.assert_truthy(joined:find("401", 1, true), "error body")

render.on_event(b, { type = "agent_start" })
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "error", errorMessage = "stream boom" },
})
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
joined = table.concat(lines, "\n")
h.assert_truthy(joined:find("stream boom", 1, true), "stream error text")

-- thinking = gray text, no headers/quotes; then assistant
render.on_event(b, { type = "agent_start" })
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "thinking_delta", delta = "step one" },
})
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "thinking_delta", delta = "\nstep two" },
})
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "thinking_end" },
})
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "text_delta", delta = "final answer" },
})
-- thinking stays open through the answer; fold once on agent_end
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
joined = table.concat(lines, "\n")
h.assert_false(joined:find("### thinking", 1, true), "no thinking header")
h.assert_truthy(joined:find("step two", 1, true), "thinking still open mid-turn")
h.assert_false(joined:find("### assistant", 1, true), "no assistant header")
h.assert_truthy(joined:find("final answer", 1, true), "answer text")
render.on_event(b, { type = "agent_end" })
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
joined = table.concat(lines, "\n")
h.assert_truthy(joined:find("step one", 1, true), "thinking line1 kept as fold preview")
h.assert_false(joined:find("step two", 1, true), "thinking body auto-folded on agent_end")
local think_hint = ""
for _, m in ipairs(h.box_marks(b)) do
  local d = m[4] or {}
  if d.virt_lines_above and d.virt_lines then
    for _, chunk in ipairs(d.virt_lines[1] or {}) do
      think_hint = think_hint .. (chunk[1] or "")
    end
  end
end
h.assert_truthy(think_hint:find("ftk to expand", 1, true), "thinking fold hint on chrome")
local answer_line
for _, l in ipairs(lines) do
  if l:find("final answer", 1, true) then
    answer_line = l
    break
  end
end
h.assert_eq(answer_line, "final answer", "answer buffer text has no space pad (box virt_text insets)")
-- answer sits in an assistant box with the same ▌│ chrome as toolcall
local has_asst_box = false
local ns_list = vim.api.nvim_get_namespaces()
for name, ns in pairs(ns_list) do
  if tostring(name):match("^pi_box_") then
    local marks = vim.api.nvim_buf_get_extmarks(b, ns, 0, -1, { details = true })
    for _, m in ipairs(marks) do
      local d = m[4]
      if d and d.virt_text then
        for _, chunk in ipairs(d.virt_text) do
          if chunk[2] == "PiAsstBar" or chunk[2] == "PiAsstBorder" then
            has_asst_box = true
          end
        end
      end
      if d and (d.line_hl_group == "PiAsstBubble" or d.hl_group == "PiAsstBubble") then
        has_asst_box = true
      end
    end
  end
end
h.assert_truthy(has_asst_box, "answer boxed with left chrome")

-- successive final answers get "pi · #1", "pi · #2" (or model · #N) in the top-left label
local function collect_turn_labels(buf)
  local labels = {}
  for name, ns in pairs(vim.api.nvim_get_namespaces()) do
    if tostring(name):match("^pi_box_") then
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
        local vl = m[4] and m[4].virt_lines
        if vl then
          for _, row in ipairs(vl) do
            for _, chunk in ipairs(row) do
              local t = tostring(chunk[1])
              if chunk[2] == "PiAssistant" and t:match("· #%d+$") then
                labels[#labels + 1] = t
              end
            end
          end
        end
      end
    end
  end
  table.sort(labels)
  return labels
end
render.on_event(b, { type = "agent_start" })
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "text_delta", delta = "turn-a" },
})
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "text_end" },
})
render.on_event(b, { type = "agent_start" })
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "text_delta", delta = "turn-b" },
})
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "text_end" },
})
local turn_labels = collect_turn_labels(b)
h.assert_truthy(vim.tbl_contains(turn_labels, "pi · #1"), "first answer labeled pi · #1")
h.assert_truthy(vim.tbl_contains(turn_labels, "pi · #2"), "second answer labeled pi · #2")

-- markdown tables pad columns to display width (CJK-safe); box supplies the gutter
render.on_event(b, { type = "agent_start" })
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = {
    type = "text_delta",
    delta = "| 列1 | 列2 |\n| --- | --- |\n| a | 中文 |\n| longer | x |\n",
  },
})
local table_lines = {}
for _, l in ipairs(vim.api.nvim_buf_get_lines(b, 0, -1, false)) do
  if l:find("|", 1, true) then
    table_lines[#table_lines + 1] = l
  end
end
h.assert_truthy(#table_lines >= 4, "table rows present")
local tw = vim.fn.strdisplaywidth(table_lines[1])
for i = 2, #table_lines do
  h.assert_eq(vim.fn.strdisplaywidth(table_lines[i]), tw, "table row widths match: " .. table_lines[i])
end
h.assert_eq(table_lines[1]:match("^(%s*)"), "", "table has no space pad (box insets)")
h.assert_truthy(table_lines[1]:find("列1", 1, true), "header cell kept")

-- thinking lines have PiThinking mark
local tns = vim.api.nvim_get_namespaces()["pi_role"]
local tmarks = vim.api.nvim_buf_get_extmarks(b, tns, 0, -1, { details = true })
local has_think_hl = false
for _, m in ipairs(tmarks) do
  if m[4] and m[4].hl_group == "PiThinking" then
    has_think_hl = true
  end
end
h.assert_truthy(has_think_hl, "thinking gray hl")

-- hydrate includes thinking parts (no headers)
local hb = vim.api.nvim_create_buf(false, true)
render.setup(hb)
local n = render.hydrate(hb, {
  {
    role = "assistant",
    content = {
      { type = "thinking", thinking = "why\nnot" },
      { type = "text", text = "because" },
    },
  },
}, { footer = false })
h.assert_eq(n, 1, "hydrated one")
local hjoin = table.concat(vim.api.nvim_buf_get_lines(hb, 0, -1, false), "\n")
h.assert_false(hjoin:find("### thinking", 1, true), "no hydrate thinking header")
h.assert_truthy(hjoin:find("why", 1, true), "hydrate thinking body")
h.assert_truthy(hjoin:find("because", 1, true), "hydrate text")

-- streamed thinking stays inside exactly one dashed box, even char-by-char
render.on_event(b, { type = "agent_start" })
for ch in ("alpha beta"):gmatch(".") do
  render.on_event(b, { type = "message_update", assistantMessageEvent = { type = "thinking_delta", delta = ch } })
end
render.on_event(b, { type = "message_update", assistantMessageEvent = { type = "thinking_delta", delta = "\ngamma" } })
render.on_event(b, { type = "message_update", assistantMessageEvent = { type = "thinking_end" } })

-- scope to this box's own namespace: extmark rows drift when a boxed line is
-- rewritten (virt_lines + nvim_buf_set_lines), so row ranges are not reliable
local rows = 2 -- "alpha beta" + "gamma"
local marks = h.box_marks(b, h.last_box_ns(b))
h.assert_eq(#marks, 2 * rows + 2, "2 marks per row + 2 rules, no accumulation")

local bodies, tops, bottoms = 0, 0, 0
local right_col_by_row, body_by_row = {}, {}
local top_w, bot_w
for _, m in ipairs(marks) do
  local d = m[4] or {}
  if d.line_hl_group == "PiThinkBubble" then
    bodies = bodies + 1
    body_by_row[m[2]] = true
  end
  if d.virt_text_win_col ~= nil then
    local vt = d.virt_text[1]
    h.assert_eq(vt[2], "PiThinkBorder", "right border uses the role border hl")
    h.assert_truthy(d.virt_text_repeat_linebreak, "right border repeats on soft-wrapped rows")
    right_col_by_row[m[2]] = d.virt_text_win_col
  end
  if d.virt_lines then
    local s = ""
    for _, chunk in ipairs(d.virt_lines[1] or {}) do
      s = s .. tostring(chunk[1])
    end
    if d.virt_lines_above then
      tops = tops + 1
      top_w = vim.fn.strdisplaywidth(s)
    else
      bottoms = bottoms + 1
      bot_w = vim.fn.strdisplaywidth(s)
    end
  end
end
h.assert_eq(bodies, rows, "one body mark per thinking row")
h.assert_eq(tops, 1, "exactly one top rule")
h.assert_eq(bottoms, 1, "exactly one bottom rule")

-- every boxed row pins the right border at the same window column; top/bottom
-- rules fill exactly the text area (display-width aware for CJK/ambiwidth)
local info = vim.fn.getwininfo(win)[1]
local avail = info.width - (info.textoff or 0)
h.assert_eq(vim.tbl_count(right_col_by_row), rows, "one right border per row")
local cols = vim.tbl_values(right_col_by_row)
table.sort(cols)
h.assert_eq(cols[1], cols[#cols], "all right borders share one column")
h.assert_eq(cols[1], avail - vim.fn.strdisplaywidth("┊"), "right border at window edge")
h.assert_eq(top_w, avail, "top rule fills the text area")
h.assert_eq(bot_w, avail, "bottom rule fills the text area")
h.assert_eq(top_w, bot_w, "top and bottom rules match")

-- hammering one line with deltas must not stack marks (hard-wrap may add a
-- row or two in a narrow window; still O(rows), never O(deltas))
render.on_event(b, { type = "message_update", assistantMessageEvent = { type = "thinking_delta", delta = "z" } })
for _ = 1, 40 do
  render.on_event(b, { type = "message_update", assistantMessageEvent = { type = "thinking_delta", delta = "x" } })
end
render.on_event(b, { type = "message_update", assistantMessageEvent = { type = "thinking_end" } })
local after = h.box_marks(b, h.last_box_ns(b))
local body_n = 0
for _, m in ipairs(after) do
  if m[4] and m[4].line_hl_group == "PiThinkBubble" then
    body_n = body_n + 1
  end
end
h.assert_truthy(body_n >= 1 and body_n <= 3, "few body rows after 41 deltas, not one per char")
h.assert_eq(#after, 2 * body_n + 2, "2 marks per row + 2 rules, no accumulation")

-- pending review hint after agent_end; clears when touched empties
package.loaded["pi.session"] = nil
local session = require("pi.session")
session.reset()
session.record_edit({ path = "r1", rel = "r1", before = { "x" }, buf = 0 })
session.record_edit({ path = "r2", rel = "r2", before = { "y" }, buf = 0 })
render.on_event(b, { type = "agent_end" })
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
joined = table.concat(lines, "\n")
h.assert_truthy(joined:find("◎ 2 files · <C-r> preview · <C-o> all", 1, true), "plural review hint")
session.remove_touched(1)
render.note_pending_review(b)
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
joined = table.concat(lines, "\n")
h.assert_truthy(joined:find("◎ 1 file · <C-r> preview · <C-o> all", 1, true), "singular review hint")
h.assert_false(joined:find("◎ 2 files", 1, true), "count updated in place")
session.remove_touched(1)
render.note_pending_review(b)
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
joined = table.concat(lines, "\n")
h.assert_false(joined:find("<C-r> preview", 1, true), "hint removed when empty")

pcall(vim.api.nvim_win_close, win, true)
pcall(vim.api.nvim_win_close, other, true)
