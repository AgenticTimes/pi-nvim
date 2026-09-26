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
    return false
  end,
  open = function() end,
  close = function() end,
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
h.assert_truthy(slots.create(), "sat2")
h.assert_eq(slots.primary().id, 1, "primary starts 1")
h.assert_truthy(slots.focus_by_id(3), "focus #3")
h.assert_eq(slots.primary().id, 3, "primary is 3")
h.assert_false(slots.focus_by_id(99), "missing id fails")

for _, s in ipairs(slots.live()) do
  if s.id == 2 then
    s.parked = true
  end
end
h.assert_truthy(slots.focus_by_id(2), "focus parked")
h.assert_eq(slots.primary().id, 2, "primary is 2")
for _, s in ipairs(slots.live()) do
  if s.id == 2 then
    h.assert_false(s.parked, "slot 2 unparked")
  end
end

slots._reset_for_test()
print("OK slots_focus_test")
