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

statusline.start()
statusline.start()
h.assert_truthy(statusline.lualine() ~= "", "still busy")
statusline.stop()
statusline.stop()
h.assert_eq(statusline.lualine(), "", "double stop idle")

statusline.start()
h.assert_eq(vim.g.pi_busy, statusline.lualine(), "g:pi_busy mirrors text")
statusline.stop()
h.assert_eq(vim.g.pi_busy, "", "g:pi_busy cleared")

-- idle with pending edits → Review · N
package.loaded["pi.session"] = nil
local session = require("pi.session")
session.reset()
session.record_edit({ path = "x", rel = "x", before = { "a" }, buf = 0 })
statusline.repaint()
h.assert_eq(statusline.lualine(), "Review · 1", "pending review cue")
session.remove_touched(1)
statusline.repaint()
h.assert_eq(statusline.lualine(), "", "cleared when no pending")

package.loaded["pi.runtime"] = {
  ensure_started = function() end,
  prompt = function() end,
  abort = function() end,
}
package.loaded["pi.render"] = nil
package.loaded["pi.ui"] = nil
local ui = require("pi.ui")
ui.open()
statusline.start()
local overlay
for _, w in ipairs(vim.api.nvim_list_wins()) do
  local cfg = vim.api.nvim_win_get_config(w)
  if cfg.relative == "win" and cfg.height == 1 and cfg.anchor == "SW" then
    overlay = w
    break
  end
end
h.assert_truthy(overlay, "busy overlay float open")
local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(overlay), 0, 1, false)[1] or ""
h.assert_truthy(line:find("Working", 1, true), "overlay shows Working: " .. line)
statusline.stop()
local still = false
for _, w in ipairs(vim.api.nvim_list_wins()) do
  local cfg = vim.api.nvim_win_get_config(w)
  if cfg.relative == "win" and cfg.height == 1 and cfg.anchor == "SW" then
    still = true
  end
end
h.assert_false(still, "overlay closed on stop")
ui.close()

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
