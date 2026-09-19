local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.session"] = nil
package.loaded["pi.host_tools"] = nil
package.loaded["pi.config"] = nil

local host = require("pi.host_tools")
local session = require("pi.session")
session.reset()

local tmp = h.root .. "/demo/_open_goto.lua"
vim.fn.writefile({ "line1", "line2", "target here" }, tmp)

local ok, msg = host.apply({ op = "open", path = tmp, line = 3, col = 0 })
h.assert_truthy(ok, "open ok: " .. tostring(msg))

ok, msg = host.apply({ op = "goto", path = tmp, line = 2, col = 0 })
h.assert_truthy(ok, "goto ok: " .. tostring(msg))
h.assert_truthy(msg:match("goto"), "goto msg")

-- cleanup
pcall(vim.fn.delete, tmp)
package.loaded["pi.session"] = nil
package.loaded["pi.host_tools"] = nil
