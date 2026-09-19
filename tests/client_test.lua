local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

local client = require("pi.client")
local events = {}
client.set_on_event(function(ev)
  table.insert(events, ev)
end)

-- partial chunks form one JSON line
client._feed_for_test('{"type":"agent_st')
client._feed_for_test('art"}\n')
h.assert_eq(#events, 1, "one event")
h.assert_eq(events[1].type, "agent_start", "type")

events = {}
client._feed_for_test('{"type":"a"}\n{"type":"b"}\n')
h.assert_eq(#events, 2, "two events")
