local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

local context = require("pi.context")
local b = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(b)
vim.api.nvim_buf_set_lines(b, 0, -1, false, { "alpha", "beta line", "gamma" })
vim.api.nvim_win_set_cursor(0, { 2, 0 })

local out = context.expand("see @this please")
h.assert_truthy(out:find("beta line", 1, true), "@this")

out = context.expand("full @buffer end")
h.assert_truthy(out:find("alpha", 1, true) and out:find("gamma", 1, true), "@buffer")
