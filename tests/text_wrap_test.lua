local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.render.text"] = nil
local text = require("pi.render.text")

-- Prefer word boundary over mid-token cut
local lines = text.wrap_line("do NOT refer to the sources", 10)
h.assert_eq(lines[1], "do NOT", "break before refer")
h.assert_truthy(not lines[1]:match("NO$"), "must not split NOT")
for _, l in ipairs(lines) do
  h.assert_truthy(text.disp_w(l) <= 10, "each line fits: " .. l)
end

-- Long token still hard-cuts
local long = string.rep("a", 25)
lines = text.wrap_line(long, 10)
h.assert_truthy(#lines >= 3, "long token yields multiple rows")
h.assert_eq(text.disp_w(lines[1]), 10, "first slice full width")

-- Short line unchanged
lines = text.wrap_line("hi", 40)
h.assert_eq(#lines, 1, "short")
h.assert_eq(lines[1], "hi", "passthrough")

print("OK text_wrap_test")
