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

require("pi.config").setup({ max_slots = 3, bootstrap = false })
local slots = require("pi.slots")
slots._reset_for_test()

h.assert_truthy(slots.create(), "sat 1")
h.assert_truthy(slots.create(), "sat 2")
h.assert_eq(slots.count(), 3, "at max")

-- at max: refuse — do NOT evict/close a right-hand satellite
local s, err = slots.create()
h.assert_false(s, "create at max fails")
h.assert_truthy(tostring(err):find("max slots", 1, true), "error mentions max: " .. tostring(err))
h.assert_eq(slots.count(), 3, "no eviction; count unchanged")

slots._reset_for_test()
package.loaded["pi.slots"] = nil
package.loaded["pi.render"] = nil
package.loaded["pi.ui"] = nil
package.loaded["pi.runtime"] = nil
package.loaded["pi.client"] = nil
package.loaded["pi.config"] = nil
print("OK slots_evict_test")
