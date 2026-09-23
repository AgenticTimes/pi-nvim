local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.statusline"] = nil
local statusline = require("pi.statusline")

h.assert_eq(statusline.lualine(), "", "idle empty")
statusline.start()
local busy = statusline.lualine()
h.assert_truthy(busy:find("Working", 1, true), "busy shows Working: " .. busy)
h.assert_truthy(busy:find("·", 1, true), "busy shows elapsed")
statusline.stop()
h.assert_eq(statusline.lualine(), "", "idle again after stop")

-- start twice is safe; stop twice is safe
statusline.start()
statusline.start()
h.assert_truthy(statusline.lualine() ~= "", "still busy")
statusline.stop()
statusline.stop()
h.assert_eq(statusline.lualine(), "", "double stop idle")

package.loaded["pi.session"] = nil
local session = require("pi.session")
session.reset()
h.assert_eq(statusline.lualine(), "", "reset idle")
session.on_event({ type = "agent_start" })
h.assert_truthy(statusline.lualine():find("Working", 1, true), "agent_start starts spinner")
session.on_event({ type = "agent_end" })
h.assert_eq(statusline.lualine(), "", "agent_end stops spinner")
session.apply_state({ isStreaming = true })
h.assert_truthy(statusline.lualine() ~= "", "isStreaming starts")
session.apply_state({ isStreaming = false })
h.assert_eq(statusline.lualine(), "", "isStreaming false stops")
session.on_event({ type = "agent_start" })
session.reset()
h.assert_eq(statusline.lualine(), "", "reset stops spinner")
