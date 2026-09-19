local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

-- Avoid starting real pi in UI open during unit test: stub runtime
package.loaded["pi.runtime"] = {
  ensure_started = function() end,
  prompt = function() end,
  abort = function() end,
}

local ui = require("pi.ui")
ui.open()
h.assert_truthy(ui.is_open(), "open")
local chat = ui.chat_buf()
local input = ui.input_buf()
h.assert_truthy(vim.api.nvim_buf_is_valid(chat), "chat")
h.assert_truthy(vim.api.nvim_buf_is_valid(input), "input")
ui.close()
h.assert_false(ui.is_open(), "closed")
