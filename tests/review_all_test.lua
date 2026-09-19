local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.session"] = nil
package.loaded["pi.review"] = nil
package.loaded["pi.config"] = nil

local session = require("pi.session")
local review = require("pi.review")
require("pi.config").opts.write_on_accept = false
session.reset()

local function make_buf(name, lines)
  local b = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(b, name)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  return b
end

local b1 = make_buf(h.root .. "/demo/_a1.lua", { "A", "x" })
local b2 = make_buf(h.root .. "/demo/_a2.lua", { "B", "y" })
session.record_edit({ path = "a1", rel = "a1", before = { "A", "ORIG1" }, buf = b1, changed_row = 2 })
session.record_edit({ path = "a2", rel = "a2", before = { "B", "ORIG2" }, buf = b2, changed_row = 2 })
h.assert_eq(#session.touched(), 2, "two pending")

review.reject_all()
h.assert_eq(#session.touched(), 0, "reject all cleared")
h.assert_eq(vim.api.nvim_buf_get_lines(b1, 0, -1, false)[2], "ORIG1", "b1 restored")
h.assert_eq(vim.api.nvim_buf_get_lines(b2, 0, -1, false)[2], "ORIG2", "b2 restored")

-- accept all keeps current content
session.record_edit({ path = "a1", rel = "a1", before = { "A", "old" }, buf = b1, changed_row = 2 })
session.record_edit({ path = "a2", rel = "a2", before = { "B", "old" }, buf = b2, changed_row = 2 })
vim.api.nvim_buf_set_lines(b1, 0, -1, false, { "A", "KEEP1" })
vim.api.nvim_buf_set_lines(b2, 0, -1, false, { "B", "KEEP2" })
review.accept_all()
h.assert_eq(#session.touched(), 0, "accept all cleared")
h.assert_eq(vim.api.nvim_buf_get_lines(b1, 0, -1, false)[2], "KEEP1", "b1 kept")
h.assert_eq(vim.api.nvim_buf_get_lines(b2, 0, -1, false)[2], "KEEP2", "b2 kept")

require("pi.config").opts.write_on_accept = true
package.loaded["pi.session"] = nil
package.loaded["pi.review"] = nil
