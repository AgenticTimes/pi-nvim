local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.session"] = nil
package.loaded["pi.review"] = nil
package.loaded["pi.config"] = nil
package.loaded["pi.runtime"] = {
  ensure_started = function() end,
  prompt = function() end,
  abort = function() end,
}
package.loaded["pi.ui"] = nil

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

local b1 = make_buf(h.root .. "/demo/_p1.lua", { "one", "AAA" })
local b2 = make_buf(h.root .. "/demo/_p2.lua", { "two", "BBB" })
session.record_edit({ path = "p1", rel = "p1", before = { "one", "aaa" }, buf = b1, changed_row = 2 })
session.record_edit({ path = "p2", rel = "p2", before = { "two", "bbb" }, buf = b2, changed_row = 2 })
h.assert_eq(#session.touched(), 2, "two touched")

-- auto_show must not open review chrome
review.auto_show()
h.assert_eq(review.current_index(), 0, "auto_show leaves idx unset")

-- preview opens latest file (no pending list required)
review.preview()
h.assert_eq(review.current_index(), 2, "preview last file")
local found_hint = false
for name, id in pairs(vim.api.nvim_get_namespaces()) do
  if name == "pi_review_hint" then
    local marks = vim.api.nvim_buf_get_extmarks(b2, id, 0, -1, { details = true })
    for _, m in ipairs(marks) do
      local d = m[4] or {}
      if d.virt_lines_above and d.virt_lines then
        local s = ""
        for _, row in ipairs(d.virt_lines or {}) do
          for _, chunk in ipairs(row or {}) do
            s = s .. tostring(chunk[1])
          end
        end
        h.assert_truthy(s:find("q close", 1, true), "preview hint: " .. s)
        h.assert_false(s:find("a/r", 1, true), "no accept/reject in hint")
        found_hint = true
      end
    end
  end
end
h.assert_truthy(found_hint, "preview paints hint")

-- preview_all opens first + list mode; next cycles
review.preview_all()
h.assert_eq(review.current_index(), 1, "preview_all first")
review.next(1)
h.assert_eq(review.current_index(), 2, "next file")

-- q / close keeps touched (preview-only)
review.close()
h.assert_eq(#session.touched(), 2, "touched kept after close")

-- accept still works via API
review.open(1, { list = true })
review.accept()
h.assert_eq(#session.touched(), 1, "accept removes one")

require("pi.ui").close()
require("pi.config").opts.write_on_accept = true
package.loaded["pi.runtime"] = nil
package.loaded["pi.ui"] = nil
package.loaded["pi.session"] = nil
package.loaded["pi.review"] = nil
