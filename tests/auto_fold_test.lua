local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.render"] = nil
package.loaded["pi.config"] = nil
require("pi.config").setup({ bootstrap = false, auto_fold = true })
local render = require("pi.render")

local b = vim.api.nvim_create_buf(false, true)
render.setup(b)
render.reset(b)

-- tool: expanded while running, auto-fold on success
render.on_event(b, {
  type = "tool_execution_start",
  toolCallId = "t1",
  toolName = "bash",
  args = { command = "echo hi" },
})
local mid = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
h.assert_truthy(mid:find("…", 1, true), "live ellipsis mark")
h.assert_truthy(mid:find("echo hi", 1, true), "live args visible")
render.on_event(b, {
  type = "tool_execution_end",
  toolCallId = "t1",
  toolName = "bash",
  isError = false,
})
local done = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
h.assert_truthy(done:find("ftt to expand", 1, true), "success auto-folded")
h.assert_false(done:find("echo hi", 1, true), "args hidden after fold")

-- error stays expanded
render.on_event(b, {
  type = "tool_execution_start",
  toolCallId = "e1",
  toolName = "bash",
  args = { command = "nope" },
})
render.on_event(b, {
  type = "tool_execution_end",
  toolCallId = "e1",
  toolName = "bash",
  isError = true,
  result = { content = { { type = "text", text = "boom" } } },
})
local errj = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
h.assert_truthy(errj:find("  ! boom", 1, true), "error body stays open")

-- thinking: stream open, end folds
render.on_event(b, { type = "agent_start" })
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "thinking_delta", delta = "alpha\nbeta\ngamma" },
})
local during = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
h.assert_truthy(during:find("beta", 1, true), "expanded while streaming")
render.on_event(b, { type = "message_update", assistantMessageEvent = { type = "thinking_end" } })
local after = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
h.assert_truthy(after:find("ftk to expand", 1, true), "thinking auto-folded")
h.assert_false(after:find("gamma", 1, true), "thinking body hidden")

print("OK auto_fold_test")
