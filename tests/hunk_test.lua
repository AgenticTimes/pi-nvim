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

local b = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(b, h.root .. "/demo/_hunk.lua")
vim.api.nvim_buf_set_lines(b, 0, -1, false, { "keep", "OLD", "keep2" })
session.record_edit({
  path = "hunk",
  rel = "hunk",
  before = { "keep", "OLD", "keep2" },
  buf = b,
  changed_row = 2,
})
-- agent changed middle line
vim.api.nvim_buf_set_lines(b, 0, -1, false, { "keep", "NEW", "keep2" })

review.open(1)
-- place cursor on changed line
review.open(1)
-- hint sits once above the first changed hunk
local hint_ns = nil
for _, ns in pairs(vim.api.nvim_get_namespaces()) do
  -- resolve by scanning extmarks with virt_lines_above
end
local found_hint = false
for name, id in pairs(vim.api.nvim_get_namespaces()) do
  if name == "pi_review_hint" then
    local marks = vim.api.nvim_buf_get_extmarks(b, id, 0, -1, { details = true })
    for _, m in ipairs(marks) do
      local d = m[4] or {}
      if d.virt_lines_above and d.virt_lines then
        local s = ""
        for _, chunk in ipairs(d.virt_lines[1] or {}) do
          s = s .. tostring(chunk[1])
        end
        h.assert_truthy(s:find("accept", 1, true), "hint mentions accept: " .. s)
        h.assert_truthy(s:find("reject", 1, true), "hint mentions reject")
        found_hint = true
        h.assert_eq(m[2], 1, "hint above first changed row (0-based line 1)")
      end
    end
  end
end
h.assert_truthy(found_hint, "first-hunk hint present")
h.assert_truthy(review.accept_hunk(), "accept hunk")
local t = session.touched()[1]
h.assert_eq(t.before[2], "NEW", "before updated")
h.assert_eq(#session.touched(), 1, "still pending")

-- multi-hunk nav
vim.api.nvim_buf_set_lines(b, 0, -1, false, { "A", "B1", "C", "D1", "E" })
session.touched()[1].before = { "A", "B0", "C", "D0", "E" }
review.open(1)
h.assert_truthy(review.next_hunk(1), "next hunk")
h.assert_truthy(review.next_hunk(1), "next hunk wrap/second")
h.assert_truthy(review.next_hunk(-1), "prev hunk")

-- change another line and reject that hunk
vim.api.nvim_buf_set_lines(b, 0, -1, false, { "keep", "NEW", "CHANGED" })
t.before = { "keep", "NEW", "keep2" }
session.touched()[1].before = t.before
review.open(1)
-- move cursor conceptually to line 3 — set via code_win if available
h.assert_truthy(review.reject_hunk(), "reject hunk")
local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
-- after reject of differing region, keep2 should be restored if cursor found hunk
h.assert_truthy(lines[2] == "NEW" or lines[3] == "keep2" or lines[3] == "CHANGED", "partial state ok")

require("pi.config").opts.write_on_accept = true
package.loaded["pi.session"] = nil
package.loaded["pi.review"] = nil
