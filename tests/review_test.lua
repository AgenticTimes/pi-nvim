local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

local session = require("pi.session")
local review = require("pi.review")
session.reset()

local function make_buf(name, lines)
  local b = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(b, name)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  return b
end

local b1 = make_buf(h.root .. "/demo/_t1.lua", { "one", "AAA" })
local b2 = make_buf(h.root .. "/demo/_t2.lua", { "two", "BBB" })
session.record_edit({ path = "t1", rel = "t1", before = { "one", "aaa" }, buf = b1, changed_row = 2 })
session.record_edit({ path = "t2", rel = "t2", before = { "two", "bbb" }, buf = b2, changed_row = 2 })
h.assert_eq(#session.touched(), 2, "two touched")

-- reject restores before
vim.api.nvim_buf_set_lines(b1, 0, -1, false, { "one", "CHANGED" })
session.touched()[1].before = { "one", "ORIG" }
-- manually set file_idx by opening
review.open(1)
h.assert_eq(review.current_index(), 1, "idx")
review.reject()
local lines = vim.api.nvim_buf_get_lines(b1, 0, -1, false)
h.assert_eq(lines[2], "ORIG", "restored")
h.assert_eq(#session.touched(), 1, "one left")

review.open(1)
local before_accept = vim.api.nvim_buf_get_lines(b2, 0, -1, false)
require("pi.config").opts.write_on_accept = false
review.accept()
h.assert_eq(#session.touched(), 0, "empty after accept")
local after = vim.api.nvim_buf_get_lines(b2, 0, -1, false)
h.assert_eq(after[2], before_accept[2], "after kept")
require("pi.config").opts.write_on_accept = true
