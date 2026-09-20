local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.render"] = nil
local render = require("pi.render")
local b = vim.api.nvim_create_buf(false, true)
render.setup(b)
render.reset(b)

-- 5 identical successful reads → one collapsed line
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

local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
local tool_lines = {}
for _, l in ipairs(lines) do
  if l:match("^⚙") then
    table.insert(tool_lines, l)
  end
end
h.assert_eq(#tool_lines, 1, "collapsed to one line: " .. vim.inspect(tool_lines))
h.assert_truthy(tool_lines[1]:find("×5", 1, true), "has ×5: " .. tool_lines[1])
h.assert_truthy(tool_lines[1]:find("✓", 1, true), "ok mark")

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
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
tool_lines = {}
for _, l in ipairs(lines) do
  if l:match("^⚙") then
    table.insert(tool_lines, l)
  end
end
h.assert_eq(#tool_lines, 2, "second path new line")

-- tool call arguments are rendered inside the tool box (its own buffer)
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
local tjoin = table.concat(vim.api.nvim_buf_get_lines(tb, 0, -1, false), "\n")
h.assert_truthy(tjoin:find("  path: demo/sample.lua", 1, true), "read arg line: " .. tjoin)
h.assert_truthy(tjoin:find("  offset: 10", 1, true), "offset arg line")
h.assert_truthy(tjoin:find("  limit: 20", 1, true), "limit arg line")
h.assert_truthy(tjoin:find("  $ git status --short", 1, true), "bash command shown: " .. tjoin)
h.assert_false(tjoin:find("command:", 1, true), "bash uses $ form, not command:")
h.assert_truthy(tjoin:find("  ! command not found", 1, true), "tool error text")
h.assert_truthy(tjoin:find("✗", 1, true), "failure mark")
-- the three tool calls form one contiguous box
local tool_boxes = 0
for _, b in ipairs(vim.api.nvim_buf_get_extmarks(tb, h.last_box_ns(tb), 0, -1, { details = true })) do
  if (b[4] or {}).virt_lines then
    tool_boxes = tool_boxes + 1
  end
end
h.assert_eq(tool_boxes, 2, "one top + one bottom rule for the whole batch")


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
-- find last assistant block
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
h.assert_eq(vim.api.nvim_win_get_cursor(win)[1], vim.api.nvim_buf_line_count(b), "followed to bottom")

render.unstick()
vim.api.nvim_win_set_cursor(win, { 2, 0 })
render.follow(b, false, chat_win)
h.assert_eq(vim.api.nvim_win_get_cursor(win)[1], 2, "unstick + follow(false) keeps cursor")
render.follow(b, true, chat_win)
h.assert_eq(vim.api.nvim_win_get_cursor(win)[1], vim.api.nvim_buf_line_count(b), "force follows")

-- multiline append must not error (nvim forbids \\n in a single set_lines item)
local before = vim.api.nvim_buf_line_count(b)
render.append(b, "line-a\nline-b\nline-c")
local after = vim.api.nvim_buf_get_lines(b, before, -1, false)
h.assert_eq(#after, 3, "split into 3 lines")
h.assert_eq(after[1], "line-a", "a")
h.assert_eq(after[3], "line-c", "c")

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
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
joined = table.concat(lines, "\n")
h.assert_false(joined:find("### thinking", 1, true), "no thinking header")
h.assert_truthy(joined:find("step one", 1, true), "thinking line1")
h.assert_truthy(joined:find("step two", 1, true), "thinking line2")
h.assert_false(joined:find("### assistant", 1, true), "no assistant header")
h.assert_truthy(joined:find("final answer", 1, true), "answer text")
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
local eol_by_row, body_by_row = {}, {}
for _, m in ipairs(marks) do
  local d = m[4] or {}
  if d.line_hl_group == "PiThinkBubble" then
    bodies = bodies + 1
    body_by_row[m[2]] = true
  end
  if d.virt_text_pos == "eol" then
    local vt = d.virt_text[1]
    h.assert_eq(vt[2], "PiThinkBorder", "right border uses the role border hl")
    eol_by_row[m[2]] = vim.fn.strdisplaywidth(vt[1])
  end
  for _, _ in ipairs(d.virt_lines or {}) do
    if d.virt_lines_above then
      tops = tops + 1
    else
      bottoms = bottoms + 1
    end
  end
end
h.assert_eq(bodies, rows, "one body mark per thinking row")
h.assert_eq(tops, 1, "exactly one top rule")
h.assert_eq(bottoms, 1, "exactly one bottom rule")

-- every boxed row pads out to the same inner width (border lands on the box edge)
local info = vim.fn.getwininfo(win)[1]
local inner = math.max(10, info.width - (info.textoff or 0) - 2)
local widths = {}
for row in pairs(body_by_row) do
  h.assert_truthy(eol_by_row[row], "row has a right border")
  widths[row] = eol_by_row[row]
end
h.assert_eq(vim.tbl_count(widths), rows, "one right border per row")
-- pad = inner - 1 - content_w, so pad + 1 + content_w == inner for every row
local pads = vim.tbl_values(widths)
table.sort(pads)
h.assert_eq(pads[1] + 10, pads[#pads] + 5, "both rows pad out to one inner width")
h.assert_eq(pads[#pads] + 5, inner, "right border lands on the box edge")

-- hammering one line with deltas must not stack marks
render.on_event(b, { type = "message_update", assistantMessageEvent = { type = "thinking_delta", delta = "z" } })
for _ = 1, 40 do
  render.on_event(b, { type = "message_update", assistantMessageEvent = { type = "thinking_delta", delta = "x" } })
end
render.on_event(b, { type = "message_update", assistantMessageEvent = { type = "thinking_end" } })
h.assert_eq(#h.box_marks(b, h.last_box_ns(b)), 2 + 2, "no mark accumulation after 41 deltas into one row")

pcall(vim.api.nvim_win_close, win, true)
pcall(vim.api.nvim_win_close, other, true)
