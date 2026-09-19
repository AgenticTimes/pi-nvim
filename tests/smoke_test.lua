-- Minimal smoke: config defaults load
local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

-- fresh module state for this file
package.loaded["pi.config"] = nil
package.loaded["pi"] = nil
package.loaded["pi.init"] = nil

local config = require("pi.config")
h.assert_eq(config.opts.keys.accept, "a", "accept key")
h.assert_eq(config.opts.write_on_accept, true, "default write_on_accept")

local pi = require("pi")
pi.setup({ write_on_accept = false })
h.assert_eq(require("pi.config").opts.write_on_accept, false, "setup merge false")
pi.setup({ write_on_accept = true })
h.assert_eq(require("pi.config").opts.write_on_accept, true, "setup merge true")
