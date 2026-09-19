local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.inspect"] = nil
local insp = require("pi.inspect")
local lines = insp._format_for_test({ a = 1, b = { c = "x" } })
h.assert_truthy(#lines > 0, "has lines")
h.assert_truthy(table.concat(lines, "\n"):find("a", 1, true), "has a")
