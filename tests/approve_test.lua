local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

local sent = {}
package.loaded["pi.client"] = {
  send = function(msg)
    table.insert(sent, msg)
  end,
}
package.loaded["pi.config"] = nil
package.loaded["pi.approve"] = nil
require("pi.config").setup({ approve = "ask" })

-- stub confirm to auto-yes without UI
vim.fn.confirm = function()
  return 1
end

local approve = require("pi.approve")
approve.reset_sticky()
approve.set_mode("ask")

-- host title should be ignored
h.assert_false(
  approve.handle({
    type = "extension_ui_request",
    id = "x",
    method = "input",
    title = "__nvim_host__",
  }),
  "skip host"
)

sent = {}
local handled = approve.handle({
  type = "extension_ui_request",
  id = "c1",
  method = "confirm",
  title = "Allow bash?",
  message = "rm -rf /",
})
h.assert_truthy(handled, "confirm handled")
-- schedule runs in same tick for our stub? vim.schedule needs wait
vim.wait(50, function()
  return #sent > 0
end, 10)
h.assert_eq(#sent, 1, "one response")
h.assert_eq(sent[1].type, "extension_ui_response", "resp type")
h.assert_eq(sent[1].confirmed, true, "confirmed")

package.loaded["pi.client"] = nil
package.loaded["pi.approve"] = nil
