local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.slots"] = nil
package.loaded["pi.config"] = nil
package.loaded["pi.client"] = nil
package.loaded["pi.render"] = {
  setup = function() end,
  reset = function() end,
  on_event = function() end,
  stick = function() end,
  toggle_tool_at_cursor = function()
    return false
  end,
  jump_message = function() end,
  attach_scroll = function() end,
  follow = function() end,
  toggle_fold_kind = function() end,
}
local closed = {}
package.loaded["pi.runtime"] = {
  bind_events = function() end,
  start_job = function(client)
    client.job_id = 1
    return 1
  end,
  ensure_started = function() end,
}
package.loaded["pi.ui"] = {
  chat_buf = function()
    return vim.api.nvim_create_buf(false, true)
  end,
  chat_win = function()
    return nil
  end,
  is_open = function()
    return true
  end,
  open = function() end,
  close = function()
    closed.ui = true
  end,
  adopt_chat_buf = function() end,
  adopt_chat_win = function() end,
  open_input = function() end,
}
package.loaded["pi.session"] = {
  get = function()
    return { status = "idle", session_name = nil }
  end,
}
package.loaded["pi.statusline"] = { repaint = function() end }

require("pi.config").setup({ bootstrap = false })
local slots = require("pi.slots")
slots._reset_for_test()

h.assert_truthy(slots.create(), "sat")
-- promote #2 to master; #1 (default) becomes satellite
h.assert_truthy(slots.focus_by_id(2), "focus 2")
slots.show()

-- fake wins on both slots
local live = slots.live()
local wins_before = {}
for _, s in ipairs(live) do
  local w = vim.api.nvim_open_win(s.chat_buf, false, {
    relative = "editor",
    row = 1,
    col = 1 + (s.id - 1) * 20,
    width = 18,
    height = 5,
    style = "minimal",
    border = "single",
  })
  s.win = w
  wins_before[s.id] = w
end

slots.hide()

for id, w in pairs(wins_before) do
  h.assert_false(vim.api.nvim_win_is_valid(w), "slot #" .. id .. " win closed after hide")
end
for _, s in ipairs(slots.live()) do
  h.assert_eq(s.win, nil, "slot #" .. s.id .. " win cleared")
end
h.assert_truthy(closed.ui, "ui.close called")

slots._reset_for_test()
print("OK slots_hide_after_promote_test")
