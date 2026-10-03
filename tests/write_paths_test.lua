local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.render.write_paths"] = nil
local W = require("pi.render.write_paths")

-- unit: bash path parse
local p1 = W.bash_write_paths("cat > /tmp/pi_wp_a.md <<'EOF'\nhello\nEOF")
h.assert_eq(#p1, 1, "one path from cat > heredoc")
h.assert_truthy(p1[1]:find("pi_wp_a%.md"), "abs path: " .. tostring(p1[1]))

local p2 = W.bash_write_paths("echo hi | tee -a demo/out.txt")
h.assert_eq(#p2, 1, "tee -a")
h.assert_truthy(p2[1]:find("out%.txt"), p2[1])

local p3 = W.bash_write_paths("echo x > /dev/null")
h.assert_eq(#p3, 0, "skip /dev/null")

local p4 = W.extract_write_paths("nvim_replace_in_buffer", { path = "demo/x.lua" })
h.assert_eq(#p4, 1, "replace path")

-- integration: bash write → mini-diff chrome
package.loaded["pi.render"] = nil
package.loaded["pi.render.tools"] = nil
package.loaded["pi.config"] = nil
package.loaded["pi.session"] = nil
require("pi.config").setup({ bootstrap = false, auto_fold = true })
local render = require("pi.render")
local session = require("pi.session")
session.reset()

local target = h.root .. "/demo/_wp_bash.md"
pcall(vim.fn.delete, target)
vim.fn.writefile({ "OLD_LINE", "keep" }, target)

local chat = vim.api.nvim_create_buf(false, true)
render.setup(chat)
render.reset(chat)

local cmd = string.format("cat > %s <<'EOF'\nNEW_LINE\nkeep\nEOF", target)
render.on_event(chat, {
  type = "tool_execution_start",
  toolCallId = "b1",
  toolName = "bash",
  args = { command = cmd },
})
-- simulate the write finishing (agent would do this between start/end)
vim.fn.writefile({ "NEW_LINE", "keep" }, target)
render.on_event(chat, {
  type = "tool_execution_end",
  toolCallId = "b1",
  toolName = "bash",
  isError = false,
})

local mid = table.concat(vim.api.nvim_buf_get_lines(chat, 0, -1, false), "\n")
h.assert_truthy(mid:find("- OLD_LINE", 1, true) or mid:find("%- OLD_LINE"), "diff minus: " .. mid)
h.assert_truthy(mid:find("+ NEW_LINE", 1, true) or mid:find("%+ NEW_LINE"), "diff plus: " .. mid)
h.assert_false(mid:find("cat >", 1, true), "heredoc command hidden when diff shown: " .. mid)

local top = ""
for _, m in ipairs(h.box_marks(chat, h.last_box_ns(chat))) do
  local d = m[4] or {}
  if d.virt_lines_above and d.virt_lines then
    for _, chunk in ipairs(d.virt_lines[1] or {}) do
      top = top .. (chunk[1] or "")
    end
  end
end
h.assert_truthy(top:find("_wp_bash", 1, true), "chrome path: " .. top)
h.assert_truthy(top:find("<C-r> full diff", 1, true), "chrome C-r: " .. top)

pcall(vim.fn.delete, target)
print("OK write_paths_test")
