local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.slots"] = nil
package.loaded["pi.config"] = nil
require("pi.config").setup({ bootstrap = false })
local slots = require("pi.slots")

-- Pure sort: busy (3) before content (2) before idle (1); tie → lower id
local ranks = { [1] = 1, [2] = 3, [3] = 2, [4] = 3, [5] = 1 }
local ordered = slots.sort_ids_by_priority({ 1, 2, 3, 4, 5 }, function(id)
  return ranks[id]
end)
h.assert_eq(ordered[1], 2, "first busy (lowest id among busy)")
h.assert_eq(ordered[2], 4, "second busy")
h.assert_eq(ordered[3], 3, "contentful next")
h.assert_eq(ordered[4], 1, "idle lower id")
h.assert_eq(ordered[5], 5, "idle higher id last")

-- User focus stays left master; busy sats only float to top of the right stack.
-- Simulate: primary=1 (user focused idle), sats ordered busy-first 4,2,3
local lay = slots.compute_layout({
  cols = 120,
  lines = 50,
  chrome = 2,
  ids = { 1, 4, 2, 3 },
  primary = 1,
  margin = 1,
  min_w = 24,
  min_h = 6,
})
h.assert_truthy(lay[1].focused, "user focus remains master")
h.assert_truthy(lay[1].col < lay[4].col, "master left of sats")
h.assert_truthy(lay[4].row < lay[2].row, "busier sat higher in stack")
h.assert_truthy(lay[2].row <= lay[3].row, "busy above content/idle")

h.assert_eq(slots.layout_priority({ status = "busy" }), 3, "busy rank")
h.assert_eq(slots.layout_priority({ status = "idle", goal = "x" }), 2, "content rank")
h.assert_eq(slots.layout_priority({ status = "idle" }), 1, "idle rank")

print("OK slots_priority_test")
