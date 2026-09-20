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
h.assert_truthy(tool_lines[1]:find("sample.lua", 1, true), "has path")
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

-- assistant text gets header
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
h.assert_truthy(joined:find("### assistant", 1, true), "assistant header")
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
h.assert_truthy(joined:find("### error", 1, true), "error header")
h.assert_truthy(joined:find("401", 1, true), "error body")

render.on_event(b, { type = "agent_start" })
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "error", errorMessage = "stream boom" },
})
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
joined = table.concat(lines, "\n")
h.assert_truthy(joined:find("stream boom", 1, true), "stream error text")

-- thinking streams before assistant text (blockquote)
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
h.assert_truthy(joined:find("### thinking", 1, true), "thinking header")
h.assert_truthy(joined:find("> step one", 1, true), "thinking quoted")
h.assert_truthy(joined:find("> step two", 1, true), "thinking line2")
h.assert_truthy(joined:find("### assistant", 1, true), "assistant after thinking")
h.assert_truthy(joined:find("final answer", 1, true), "answer text")

-- hydrate includes thinking parts
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
h.assert_truthy(hjoin:find("### thinking", 1, true), "hydrate thinking")
h.assert_truthy(hjoin:find("> why", 1, true), "hydrate quote")
h.assert_truthy(hjoin:find("because", 1, true), "hydrate text")

pcall(vim.api.nvim_win_close, win, true)
pcall(vim.api.nvim_win_close, other, true)
