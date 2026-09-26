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
h.assert_eq(lay[1].zindex, 49, "primary z under sats for shared edges")
h.assert_eq(lay[2].zindex, 50, "sat z")

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

-- flush: last incomplete row stretches to full stack width (no hole)
local five = slots.compute_layout({
  cols = 160,
  lines = 28,
  chrome = 2,
  ids = { 1, 2, 3, 4, 5, 6 },
  primary = 1,
  margin = 1,
  min_w = 24,
  min_h = 6,
})
h.assert_eq(five[1].row, five[2].row, "master and first sat share top")
h.assert_eq(five[2].col, five[1].col + five[1].width + 1, "sat abuts master (gap=1 for shared border)")
local max_row = 0
for id = 2, 6 do
  if five[id].row > max_row then
    max_row = five[id].row
  end
end
local last_left, last_right = nil, nil
for id = 2, 6 do
  if five[id].row == max_row then
    local L = five[id].col
    local R = five[id].col + five[id].width
    if not last_left or L < last_left then
      last_left = L
    end
    if not last_right or R > last_right then
      last_right = R
    end
  end
end
local first_row = five[2].row
local fr_left, fr_right = nil, nil
for id = 2, 6 do
  if five[id].row == first_row then
    local L = five[id].col
    local R = five[id].col + five[id].width
    if not fr_left or L < fr_left then
      fr_left = L
    end
    if not fr_right or R > fr_right then
      fr_right = R
    end
  end
end
h.assert_eq(last_left, fr_left, "last row starts at stack left")
h.assert_eq(last_right, fr_right, "last row fills same width as first row (no hole)")

-- neighbor junctions: master touches sats → E/W; stacked sats → N/S
h.assert_truthy(five[1].nbr and five[1].nbr.E, "master has east neighbor")
h.assert_truthy(five[2].nbr and five[2].nbr.W, "first sat has west neighbor (master)")
local has_ns = false
for id = 2, 6 do
  if five[id].nbr and (five[id].nbr.N or five[id].nbr.S) then
    has_ns = true
    break
  end
end
h.assert_truthy(has_ns, "some sats share N/S edge")

-- stacked sat: northern omits bottom so southern title isn't overwritten
local dummy = { id = 2 }
local north = slots.border_for(dummy, false, { S = true, W = true })
h.assert_eq(north[6][1], "", "north omits bottom when nbr.S")
h.assert_eq(north[5][1], "", "north omits br when nbr.S")
h.assert_eq(north[7][1], "", "north omits bl when nbr.S")
local south = slots.border_for(dummy, false, { N = true, W = true })
h.assert_eq(south[2][1], "─", "south keeps top for title")
h.assert_eq(south[6][1], "─", "south keeps bottom")
h.assert_eq(south[1][1], "┼", "south TL junction with N+W")

print("OK slots_layout_test")
