local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.render"] = nil
package.loaded["pi.render.tools"] = nil
package.loaded["pi.config"] = nil
package.loaded["pi.session"] = nil

require("pi.config").setup({ bootstrap = false, auto_fold = true })
local tools = require("pi.render.tools")
local session = require("pi.session")
local render = require("pi.render")

-- unit: mini_diff
local before = { "keep", "OLD", "keep2", "tail" }
local after = { "keep", "NEW", "keep2", "tail" }
local lines, hidden = tools.mini_diff_lines(before, after, 8)
local joined = table.concat(lines, "\n")
h.assert_truthy(joined:find("%- OLD", 1) or joined:find("- OLD", 1, true), "removed line: " .. joined)
h.assert_truthy(joined:find("%+ NEW", 1) or joined:find("+ NEW", 1, true), "added line: " .. joined)
h.assert_eq(hidden, 0, "single hunk fully shown")

-- Body is mini-diff only; path / <C-r> live on the top-rule chrome.
local body = tools.edit_diff_lines("todo.md", before, after)
local bj = table.concat(body, "\n")
h.assert_false(bj:find("path: todo.md", 1, true), "path not in body")
h.assert_false(bj:find("<C-r> full diff", 1, true), "C-r not in body")
h.assert_truthy(bj:find("- OLD", 1, true) or bj:find("%- OLD"), "body has minus")
h.assert_truthy(bj:find("+ NEW", 1, true) or bj:find("%+ NEW"), "body has plus")

-- integration: host-style edit tool paints mini-diff; chrome holds path / C-r
session.reset()
local eb = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(eb, h.root .. "/demo/_diff_todo.md")
vim.api.nvim_buf_set_lines(eb, 0, -1, false, { "keep", "NEW", "keep2" })
session.record_edit({
  path = vim.fn.fnamemodify(h.root .. "/demo/_diff_todo.md", ":p"),
  rel = "demo/_diff_todo.md",
  before = { "keep", "OLD", "keep2" },
  buf = eb,
  changed_row = 2,
})

local chat = vim.api.nvim_create_buf(false, true)
render.setup(chat)
render.reset(chat)
render.on_event(chat, {
  type = "tool_execution_start",
  toolCallId = "ed1",
  toolName = "nvim_replace_in_buffer",
  args = { path = "demo/_diff_todo.md", old_text = "OLD", new_text = "NEW" },
})
render.on_event(chat, {
  type = "tool_execution_end",
  toolCallId = "ed1",
  toolName = "nvim_replace_in_buffer",
  isError = false,
})
local mid = table.concat(vim.api.nvim_buf_get_lines(chat, 0, -1, false), "\n")
h.assert_false(mid:find("path: demo/_diff_todo.md", 1, true), "path not dumped in body: " .. mid)
h.assert_false(mid:find("replace_in_buffer", 1, true), "tool name not in body: " .. mid)
h.assert_false(mid:find("<C-r> full diff", 1, true), "C-r not in body: " .. mid)
h.assert_truthy(mid:find("- OLD", 1, true) or mid:find("%- OLD"), "diff minus: " .. mid)
h.assert_truthy(mid:find("+ NEW", 1, true) or mid:find("%+ NEW"), "diff plus: " .. mid)

-- Top-rule virt_lines: path label + <C-r> full diff hint
local top = ""
for _, m in ipairs(h.box_marks(chat, h.last_box_ns(chat))) do
  local d = m[4] or {}
  if d.virt_lines_above and d.virt_lines then
    for _, chunk in ipairs(d.virt_lines[1] or {}) do
      top = top .. (chunk[1] or "")
    end
  end
end
h.assert_truthy(top:find("diff_todo", 1, true) or top:find("_diff_todo", 1, true), "chrome label path: " .. top)
h.assert_truthy(top:find("<C-r> full diff", 1, true), "chrome C-r hint: " .. top)
h.assert_false(top:find("replace_in_buffer", 1, true), "tool name not on chrome: " .. top)

render.on_event(chat, { type = "agent_end" })
local folded = table.concat(vim.api.nvim_buf_get_lines(chat, 0, -1, false), "\n")
h.assert_truthy(folded:find("- OLD", 1, true) or folded:find("%- OLD"), "mini-diff kept after fold")
h.assert_false(folded:find("old_text:", 1, true), "raw old_text not dumped")
h.assert_false(folded:find("replace_in_buffer", 1, true), "tool name still hidden after fold")

pcall(vim.api.nvim_buf_delete, eb, { force = true })
print("OK edit_diff_test")
