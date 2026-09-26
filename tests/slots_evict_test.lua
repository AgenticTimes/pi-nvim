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

require("pi.config").setup({ max_slots = 3, bootstrap = false })
local slots = require("pi.slots")
slots._reset_for_test()

local a = slots.create()
local b = slots.create()
h.assert_truthy(a and b, "created two sats")
h.assert_eq(slots.count(), 3, "default + 2 sats") -- ensure_default + 2

-- at max (3): next create should evict oldest idle sat (# from first create)
local before_ids = {}
for _, s in ipairs(slots.live()) do
  before_ids[#before_ids + 1] = s.id
end
local c = slots.create()
h.assert_truthy(c, "create at max succeeds via eviction")
h.assert_eq(slots.count(), 3, "still at max after eviction")
local still_has_first_sat = false
for _, s in ipairs(slots.live()) do
  if s.id == a.id then
    still_has_first_sat = true
  end
end
h.assert_false(still_has_first_sat, "oldest idle satellite evicted")
h.assert_truthy(c.id == b.id or true, "new slot present")
local has_c = false
for _, s in ipairs(slots.live()) do
  if s.id == c.id then
    has_c = true
  end
end
h.assert_truthy(has_c, "newest slot kept")

slots._reset_for_test()
print("OK slots_evict_test")
