local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.session"] = {
  get = function()
    return { status = "idle", auto_compaction = true }
  end,
}

local ind = require("pi.compact_indicator")
ind.update({ compacting = true, auto = true })
h.assert_truthy(ind.floating_win and vim.api.nvim_win_is_valid(ind.floating_win), "compacting float open")
local lines = vim.api.nvim_buf_get_lines(ind.floating_buf, 0, -1, false)
h.assert_eq(lines[1], " C… ", "compacting text")

ind.update({ compacting = false, auto = true })
lines = vim.api.nvim_buf_get_lines(ind.floating_buf, 0, -1, false)
h.assert_eq(lines[1], " AC ", "auto-compact text")

ind.update({ compacting = false, auto = false })
h.assert_false(ind.floating_win and vim.api.nvim_win_is_valid(ind.floating_win or -1), "hidden when auto off")

print("OK compact_indicator_test")
