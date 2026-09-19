local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

local sent = {}
package.loaded["pi.client"] = {
  send = function(msg)
    table.insert(sent, msg)
  end,
}
package.loaded["pi.host_tools"] = { HOST_TITLE = "__nvim_host__" }
package.loaded["pi.config"] = nil
package.loaded["pi.approve"] = nil

require("pi.config").setup({ approve = "ask" })
local approve = require("pi.approve")

-- auto mode: immediate yes
approve.set_mode("auto")
sent = {}
h.assert_truthy(
  approve.handle({
    type = "extension_ui_request",
    id = "a1",
    method = "confirm",
    title = "Dangerous bash",
    message = "rm -rf",
  }),
  "auto handled"
)
h.assert_eq(sent[1].confirmed, true, "auto yes")

-- deny mode
approve.set_mode("deny")
sent = {}
approve.handle({
  type = "extension_ui_request",
  id = "a2",
  method = "confirm",
  title = "x",
  message = "y",
})
h.assert_eq(sent[1].confirmed, false, "deny no")

-- smart: safe title auto-yes
approve.set_mode("smart")
sent = {}
approve.handle({
  type = "extension_ui_request",
  id = "a3",
  method = "confirm",
  title = "Allow read file",
  message = "foo",
})
h.assert_eq(sent[1].confirmed, true, "smart safe yes")

-- sticky always
approve.set_mode("ask")
approve.reset_sticky()
vim.fn.confirm = function()
  return 3 -- Always
end
sent = {}
approve.handle({
  type = "extension_ui_request",
  id = "a4",
  method = "confirm",
  title = "bash?",
  message = "ls",
})
vim.wait(50, function()
  return #sent > 0
end, 10)
h.assert_eq(sent[1].confirmed, true, "always yes")
-- next confirm should sticky
sent = {}
approve.handle({
  type = "extension_ui_request",
  id = "a5",
  method = "confirm",
  title = "bash again",
  message = "ls",
})
h.assert_eq(sent[1].confirmed, true, "sticky")

approve.cycle_mode()
h.assert_truthy(approve.mode() ~= nil, "cycled")

package.loaded["pi.client"] = nil
package.loaded["pi.approve"] = nil
