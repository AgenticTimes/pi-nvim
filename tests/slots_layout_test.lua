local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.slots"] = nil
local slots = require("pi.slots")

-- single primary fills usable area
local one = slots.compute_layout({
  cols = 100,
  lines = 40,
  chrome = 2,
  ids = { 1 },
  primary = 1,
  margin = 1,
})
h.assert_truthy(one[1], "primary geo")
h.assert_eq(one[1].row, 1, "row margin")
h.assert_eq(one[1].col, 1, "col margin")
h.assert_truthy(one[1].focused, "focused")
h.assert_truthy(one[1].width >= 20, "width")
h.assert_truthy(one[1].height >= 8, "height")

-- master left + stack right (3 slots)
local lay = slots.compute_layout({
  cols = 120,
  lines = 50,
  chrome = 2,
  ids = { 1, 2, 3 },
  primary = 1,
  margin = 1,
})
h.assert_truthy(lay[1] and lay[2] and lay[3], "all geos")
h.assert_truthy(lay[1].focused, "primary focused")
h.assert_false(lay[2].focused, "sat not focused")
h.assert_truthy(lay[1].width > lay[2].width, "master wider")
h.assert_truthy(lay[1].height > lay[2].height, "master taller than one sat")
h.assert_eq(lay[1].height, lay[2].height + 1 + lay[3].height, "stack fills master height (+gap)")
h.assert_truthy(lay[2].col > lay[1].col, "stack to the right of master")
h.assert_eq(lay[2].col, lay[3].col, "sats same column")
h.assert_truthy(lay[3].row > lay[2].row, "sats stacked vertically")
h.assert_eq(lay[1].zindex, 52, "primary z")
h.assert_eq(lay[2].zindex, 48, "sat z")

-- promote: new primary becomes left master
local lay2 = slots.compute_layout({
  cols = 120,
  lines = 50,
  chrome = 2,
  ids = { 1, 2 },
  primary = 2,
  margin = 1,
})
h.assert_truthy(lay2[2].focused, "promoted focused")
h.assert_truthy(lay2[2].width > lay2[1].width, "promoted is master")
h.assert_truthy(lay2[1].col > lay2[2].col, "old primary moves to stack")

-- as slots fill, master (largest) shrinks; stack widens (not the reverse)
local few = slots.compute_layout({
  cols = 120,
  lines = 50,
  chrome = 2,
  ids = { 1, 2 },
  primary = 1,
  margin = 1,
})
local many = slots.compute_layout({
  cols = 120,
  lines = 50,
  chrome = 2,
  ids = { 1, 2, 3, 4, 5 },
  primary = 1,
  margin = 1,
})
h.assert_truthy(many[1].width < few[1].width, "master shrinks when more slots")
-- stack column width comes from master; individual sat width may split across cols
h.assert_truthy(many[1].width + many[2].width <= few[1].width + few[2].width + 2, "total width conserved")

-- cramped height: steal width from master (multi-col stack), keep sat height readable
local cramped = slots.compute_layout({
  cols = 120,
  lines = 28,
  chrome = 2,
  ids = { 1, 2, 3, 4, 5 },
  primary = 1,
  margin = 1,
})
local roomy = slots.compute_layout({
  cols = 120,
  lines = 60,
  chrome = 2,
  ids = { 1, 2, 3, 4, 5 },
  primary = 1,
  margin = 1,
})
h.assert_truthy(cramped[1].width < roomy[1].width, "cramped: master narrower (space for stack)")
local min_sat_h = math.min(cramped[2].height, cramped[3].height, cramped[4].height, cramped[5].height)
h.assert_truthy(min_sat_h >= 6, "cramped: sats keep readable height, not crushed")

print("OK slots_layout_test")
