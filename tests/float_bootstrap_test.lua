local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.config"] = nil
package.loaded["pi.ui"] = nil
require("pi.config").setup({
  bootstrap = false,
  summon_key = "",
  window = { layout = "float", border = "rounded", winblend = 18 },
})

local ui = require("pi.ui")
-- geometry without opening (call private via open mock)
package.loaded["pi.runtime"] = {
  ensure_started = function() end,
}
package.loaded["pi.render"] = {
  attach_scroll = function() end,
  stick = function() end,
  follow = function() end,
  setup = function() end,
  reset = function() end,
}
package.loaded["pi.session"] = {
  title_bits = function()
    return "test"
  end,
}
package.loaded["pi.statusline"] = { repaint = function() end }
package.loaded["pi.input"] = {
  setup = function() end,
}

ui.open()
h.assert_truthy(ui.is_open(), "float open")
local win = ui.chat_win()
h.assert_truthy(win and vim.api.nvim_win_is_valid(win), "chat win")
local cfg = vim.api.nvim_win_get_config(win)
h.assert_eq(cfg.relative, "editor", "editor-relative float")
h.assert_truthy(cfg.border == "rounded" or type(cfg.border) == "table", "rounded border")
local blend = vim.wo[win].winblend
h.assert_truthy(blend and blend > 0, "winblend > 0 for float layout")

ui.close()
h.assert_false(ui.is_open(), "closed")
print("OK float_bootstrap_test")
