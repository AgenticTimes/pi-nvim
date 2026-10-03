local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.render.tools"] = nil
package.loaded["pi.render"] = nil
package.loaded["pi.config"] = nil
require("pi.config").setup({ bootstrap = false, auto_fold = true })
local tools = require("pi.render.tools")
local render = require("pi.render")

-- unit: chrome labels
local sub = tools.chrome_label("subagent", { agent = "worker", task = "explore slots" }, true)
h.assert_truthy(sub:find("subagent", 1, true), "subagent label: " .. tostring(sub))
h.assert_truthy(sub:find("worker", 1, true), "agent in label: " .. tostring(sub))
h.assert_truthy(sub:find("✓", 1, true), "mark in label: " .. tostring(sub))

local bash = tools.chrome_label("bash", { command = "cat > todo.md <<'EOF'\nhi\nEOF" }, false)
h.assert_truthy(bash:find("%$ cat", 1) or bash:find("$ cat", 1, true), "bash $ cmd: " .. tostring(bash))
h.assert_truthy(bash:find("✗", 1, true), "bash fail mark")

h.assert_eq(tools.chrome_label("nvim_replace_in_buffer", { path = "x", old_text = "a", new_text = "b" }, true), nil, "edit skips chrome_label")

-- body omits agent when chrome has it
local body = tools.tool_block_lines("subagent", { agent = "worker" }, true, 1, nil, 60)
local bj = table.concat(body, "\n")
h.assert_false(bj:find("agent:", 1, true), "no agent: in body: " .. bj)
h.assert_false(bj:find("⚙ subagent", 1, true), "no ⚙ header in chrome body: " .. bj)

local bash_body = tools.tool_block_lines("bash", { command = "echo hi" }, true, 1, nil, 60)
local bb = table.concat(bash_body, "\n")
h.assert_false(bb:find("%$ echo", 1) or bb:find("$ echo", 1, true), "command not dumped in body: " .. bb)

-- integration: paint chrome on tool bubble
local chat = vim.api.nvim_create_buf(false, true)
render.setup(chat)
render.reset(chat)
render.on_event(chat, {
  type = "tool_execution_start",
  toolCallId = "s1",
  toolName = "subagent",
  args = { agent = "worker", task = "short" },
})
render.on_event(chat, {
  type = "tool_execution_end",
  toolCallId = "s1",
  toolName = "subagent",
  isError = false,
})

local top = ""
for _, m in ipairs(h.box_marks(chat, h.last_box_ns(chat))) do
  local d = m[4] or {}
  if d.virt_lines_above and d.virt_lines then
    for _, chunk in ipairs(d.virt_lines[1] or {}) do
      top = top .. (chunk[1] or "")
    end
  end
end
h.assert_truthy(top:find("subagent", 1, true), "chrome has subagent: " .. top)
h.assert_truthy(top:find("worker", 1, true), "chrome has worker: " .. top)
h.assert_false(top:find("toolcall", 1, true), "default toolcall label replaced: " .. top)

local mid = table.concat(vim.api.nvim_buf_get_lines(chat, 0, -1, false), "\n")
h.assert_false(mid:find("agent: worker", 1, true), "body omits agent: " .. mid)

print("OK tool_chrome_test")
