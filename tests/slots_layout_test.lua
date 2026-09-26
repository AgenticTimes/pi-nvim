local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.slots"] = nil
package.loaded["pi.config"] = nil
require("pi.config").setup({
  slot_min_width = 24,
  slot_min_height = 6,
  max_slots = 64,
  bootstrap = false,
})
local slots = require("pi.slots")

-- single primary fills usable area
local one = slots.compute_layout({
  cols = 100,
  lines = 40,
  chrome = 2,
  ids = { 1 },
  primary = 1,
  margin = 1,
  min_w = 24,
  min_h = 6,
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
  min_w = 24,
  min_h = 6,
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
  min_w = 24,
  min_h = 6,
})
h.assert_truthy(lay2[2].focused, "promoted focused")
h.assert_truthy(lay2[2].width > lay2[1].width, "promoted is master")
h.assert_truthy(lay2[1].col > lay2[2].col, "old primary moves to stack")

-- as slots fill, master shrinks
local few = slots.compute_layout({
  cols = 120,
  lines = 50,
  chrome = 2,
  ids = { 1, 2 },
  primary = 1,
  margin = 1,
  min_w = 24,
  min_h = 6,
})
-- 7 sats on ~6 max rows → 2 stack cols → master must shrink
local many_ids = { 1 }
for i = 2, 8 do
  many_ids[#many_ids + 1] = i
end
local many = slots.compute_layout({
  cols = 120,
  lines = 50,
  chrome = 2,
  ids = many_ids,
  primary = 1,
  margin = 1,
  min_w = 24,
  min_h = 6,
})
h.assert_truthy(many[1].width < few[1].width, "master shrinks when stack needs 2 cols")

-- vertical at min → horizontal split (multi-col stack)
local tall_pack = slots.compute_layout({
  cols = 160,
  lines = 28,
  chrome = 2,
  ids = many_ids,
  primary = 1,
  margin = 1,
  min_w = 24,
  min_h = 6,
})
local cols_seen = {}
for id = 2, 8 do
  cols_seen[tall_pack[id].col] = true
end
local ncol = 0
for _ in pairs(cols_seen) do
  ncol = ncol + 1
end
h.assert_truthy(ncol >= 2, "vertical min reached → horizontal split")

-- capacity: master shrinks to min_w; sats pack the rest (not stuck at 24)
local cap = slots.capacity({
  cols = 120,
  lines = 40,
  chrome = 2,
  margin = 1,
  min_w = 24,
  min_h = 6,
})
h.assert_truthy(cap >= 12, "capacity at least a dozen: " .. tostring(cap))
h.assert_truthy(cap <= 64, "capped by max_slots")

local wide = slots.capacity({
  cols = 240,
  lines = 60,
  chrome = 2,
  margin = 1,
  min_w = 24,
  min_h = 6,
})
h.assert_truthy(wide > 24, "wide screen: capacity > old hard 24: " .. tostring(wide))

-- every cell respects min grain (master+stack path)
for id = 1, 8 do
  local g = many[id]
  h.assert_truthy(g.width >= 20, "id " .. id .. " width")
  h.assert_truthy(g.height >= 5, "id " .. id .. " height")
end

print("OK slots_layout_test")
