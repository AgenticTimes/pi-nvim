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

-- footer virt_lines land on the chat buffer while busy
package.loaded["pi.runtime"] = {
  ensure_started = function() end,
  prompt = function() end,
  abort = function() end,
}
package.loaded["pi.ui"] = nil
local ui = require("pi.ui")
ui.open()
local chat = ui.chat_buf()
statusline.start()
local ns = vim.api.nvim_create_namespace("pi_busy")
local found = false
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(chat, ns, 0, -1, { details = true })) do
  local d = m[4] or {}
  if d.virt_lines then
    local t = ""
    for _, chunk in ipairs(d.virt_lines[1] or {}) do
      t = t .. tostring(chunk[1])
    end
    if t:find("Working", 1, true) then
      found = true
    end
  end
end
h.assert_truthy(found, "chat footer virt_lines show Working")
statusline.stop()
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
