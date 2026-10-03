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

-- tool: expanded while running AND after end; fold only on agent_end
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
h.assert_truthy(done:find("echo hi", 1, true), "args still visible after tool end")
h.assert_false(done:find("ftt to expand", 1, true), "not folded until agent_end")
h.assert_truthy(done:find("✓", 1, true), "success mark")

render.on_event(b, { type = "agent_end" })
local folded = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
h.assert_truthy(folded:find("echo hi", 1, true), "command preview kept when folded")
-- Fold hint lives on the top-rule chrome (short tools have no body marker).
local top = ""
for _, m in ipairs(h.box_marks(b, h.last_box_ns(b))) do
  local d = m[4] or {}
  if d.virt_lines_above and d.virt_lines then
    for _, chunk in ipairs(d.virt_lines[1] or {}) do
      top = top .. (chunk[1] or "")
    end
  end
end
h.assert_truthy(top:find("ftt to expand", 1, true), "folded on agent_end (chrome): " .. top)
-- multi-arg body beyond the first preview line stays hidden (N/A for one-liners)

-- error stays expanded through agent_end
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
render.on_event(b, { type = "agent_end" })
local errj = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
h.assert_truthy(errj:find("  ! boom", 1, true), "error body stays open after agent_end")

-- thinking: stream open; stay expanded through thinking_end; fold on agent_end
render.on_event(b, { type = "agent_start" })
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "thinking_delta", delta = "alpha\nbeta\ngamma" },
})
local during = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
h.assert_truthy(during:find("beta", 1, true), "expanded while streaming")
render.on_event(b, { type = "message_update", assistantMessageEvent = { type = "thinking_end" } })
local after_end = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
h.assert_truthy(after_end:find("gamma", 1, true), "thinking still open after thinking_end")
render.on_event(b, { type = "agent_end" })
local after = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
h.assert_false(after:find("gamma", 1, true), "thinking body hidden after agent_end")
local think_top = ""
for _, m in ipairs(h.box_marks(b)) do
  local d = m[4] or {}
  if d.virt_lines_above and d.virt_lines then
    local s = ""
    for _, chunk in ipairs(d.virt_lines[1] or {}) do
      s = s .. (chunk[1] or "")
    end
    if s:find("ftk", 1, true) then
      think_top = s
    end
  end
end
h.assert_truthy(think_top:find("ftk to expand", 1, true), "thinking auto-folded on agent_end: " .. think_top)

print("OK auto_fold_test")
