local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.client"] = nil
local client = require("pi.client")

local a = client.new()
local b = client.new()
h.assert_truthy(a ~= b, "distinct instances")
h.assert_truthy(a ~= client.default(), "new ≠ default")

local ev_a, ev_b, ev_d = {}, {}, {}
a.set_on_event(function(ev)
  table.insert(ev_a, ev)
end)
b.set_on_event(function(ev)
  table.insert(ev_b, ev)
end)
client.set_on_event(function(ev)
  table.insert(ev_d, ev)
end)

a._feed_for_test('{"type":"from_a"}\n')
b._feed_for_test('{"type":"from_b"}\n')
client._feed_for_test('{"type":"from_default"}\n')

h.assert_eq(#ev_a, 1, "a got one")
h.assert_eq(ev_a[1].type, "from_a", "a type")
h.assert_eq(#ev_b, 1, "b got one")
h.assert_eq(ev_b[1].type, "from_b", "b type")
h.assert_eq(#ev_d, 1, "default got one")
h.assert_eq(ev_d[1].type, "from_default", "default type")
h.assert_eq(#ev_a, 1, "a isolated from b/default")
h.assert_eq(#ev_b, 1, "b isolated")

print("OK client_multi_test")
