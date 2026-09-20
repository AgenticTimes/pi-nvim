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

-- with_picker: drop zindex while open, restore on done
ui.open_input()
local input_win
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_buf(w) == ui.input_buf() then
    input_win = w
    break
  end
end
h.assert_truthy(input_win, "input win")
local z_before = vim.api.nvim_win_get_config(input_win).zindex or 60
local saw_low = false
local done_fn
ui.with_picker(function(done)
  done_fn = done
  local z = vim.api.nvim_win_get_config(input_win).zindex
  saw_low = z == 40
end)
vim.wait(200, function()
  return done_fn ~= nil
end)
h.assert_truthy(done_fn, "picker scheduled")
h.assert_truthy(saw_low, "zindex dropped to 40 during picker")
done_fn()
local z_after = vim.api.nvim_win_get_config(input_win).zindex
h.assert_eq(z_after, z_before, "zindex restored after done")

ui.close_input()
ui.close()
h.assert_false(ui.is_open(), "closed")

-- close_input must not leave chat in insert (submit closes ask while inserting)
ui.open()
ui.open_input()
-- headless -l may ignore startinsert; still exercise the stopinsert path
pcall(vim.cmd, "startinsert!")
ui.close_input()
vim.wait(80, function()
  return not vim.fn.mode():match("^[iR]")
end)
h.assert_false(vim.fn.mode():match("^[iR]"), "chat not insert after close ask")
local cw = ui.chat_win()
h.assert_truthy(cw and vim.api.nvim_win_is_valid(cw), "chat win")
h.assert_eq(vim.api.nvim_get_current_win(), cw, "focused chat")
ui.close()
