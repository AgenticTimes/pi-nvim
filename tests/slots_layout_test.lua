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
h.assert_truthy(one[1].width >= 20, "width")
h.assert_truthy(one[1].height >= 8, "height")

-- two satellites on top, primary bottom
local lay = slots.compute_layout({
  cols = 120,
  lines = 50,
  chrome = 2,
  ids = { 1, 2, 3 },
  primary = 1,
  margin = 1,
})
h.assert_truthy(lay[1] and lay[2] and lay[3], "all geos")
h.assert_truthy(lay[2].row < lay[1].row, "sat above primary")
h.assert_truthy(lay[3].row < lay[1].row, "sat2 above primary")
h.assert_eq(lay[2].row, lay[3].row, "sats same row")
h.assert_truthy(lay[2].col < lay[3].col, "sats left-to-right")
h.assert_truthy(lay[1].height > lay[2].height, "primary taller")
h.assert_eq(lay[1].zindex, 50, "primary z")
h.assert_eq(lay[2].zindex, 48, "sat z")

-- promote: primary id 2 is bottom
local lay2 = slots.compute_layout({
  cols = 120,
  lines = 50,
  chrome = 2,
  ids = { 1, 2 },
  primary = 2,
  margin = 1,
})
h.assert_truthy(lay2[2].row > lay2[1].row, "new primary below sat")

print("OK slots_layout_test")
