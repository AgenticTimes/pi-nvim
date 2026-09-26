local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

local sent = {}
package.loaded["pi.client"] = {
  is_running = function()
    return true
  end,
  send = function(obj)
    table.insert(sent, obj)
  end,
  start = function() end,
  set_on_event = function() end,
  stop = function() end,
}
package.loaded["pi.statusline"] = {
  start = function() end,
  stop = function() end,
}
package.loaded["pi.session"] = nil
package.loaded["pi.runtime"] = nil
package.loaded["pi"] = nil

require("pi.config").setup({})
local runtime = require("pi.runtime")
require("pi.session").set_status("streaming")

local ok = runtime.interrupt()
h.assert_truthy(ok, "interrupt returns true when RPC running")
h.assert_eq(#sent, 2, "interrupt sends abort + abort_bash")
h.assert_eq(sent[1].type, "abort", "first RPC is abort")
h.assert_eq(sent[2].type, "abort_bash", "second RPC is abort_bash")
h.assert_eq(require("pi.session").get().status, "idle", "status idle after interrupt")

sent = {}
require("pi").interrupt()
h.assert_eq(#sent, 2, "pi.interrupt sends abort + abort_bash")
h.assert_eq(sent[1].type, "abort", "pi.interrupt → abort RPC")

print("OK interrupt_test")
