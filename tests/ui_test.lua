local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.runtime"] = {
  ensure_started = function() end,
  prompt = function() end,
  abort = function() end,
}
package.loaded["pi.ui"] = nil
package.loaded["pi.render"] = nil
package.loaded["pi.input"] = nil
package.loaded["pi.config"] = nil

local ui = require("pi.ui")
ui.open()
h.assert_truthy(ui.is_open(), "open")
h.assert_false(ui.is_input_open(), "no input popup yet")

local chat = ui.chat_buf()
local chat_win
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_buf(w) == chat then
    chat_win = w
    break
  end
end
h.assert_truthy(chat_win, "chat win")
local cfg = vim.api.nvim_win_get_config(chat_win)
h.assert_eq(cfg.width, vim.o.columns, "chat full width")
h.assert_eq(cfg.row, 0, "row 0")
h.assert_eq(cfg.col, 0, "col 0")

ui.open_input()
h.assert_truthy(ui.is_input_open(), "input popup open")

-- in-session yank injects (do NOT setreg("+") — that pollutes macOS clipboard)
ui._set_pending_yank_for_test("CLIPBOARD_YANK")
ui.close_input()
vim.api.nvim_buf_set_lines(ui.input_buf(), 0, -1, false, { "" })
ui.open_input()
local lines = vim.api.nvim_buf_get_lines(ui.input_buf(), 0, -1, false)
h.assert_eq(table.concat(lines, "\n"), "CLIPBOARD_YANK", "injected pending yank")

-- no pending yank → empty box (not leftover / OS clipboard)
ui.close_input()
ui._set_pending_yank_for_test(nil)
vim.api.nvim_buf_set_lines(ui.input_buf(), 0, -1, false, { "STALE" })
ui.open_input()
lines = vim.api.nvim_buf_get_lines(ui.input_buf(), 0, -1, false)
h.assert_eq(table.concat(lines, "\n"), "", "empty when no yank")

ui.close_input()
h.assert_false(ui.is_input_open(), "input closed")
h.assert_truthy(ui.is_open(), "chat still open")

ui.close()
h.assert_false(ui.is_open(), "closed")
