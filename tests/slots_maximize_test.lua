local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.slots"] = nil
package.loaded["pi.config"] = nil
package.loaded["pi.client"] = nil
package.loaded["pi.notify"] = { soft_notify = function() end }
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
  ensure_backdrop = function() end,
}
package.loaded["pi.session"] = {
  get = function()
    return { status = "idle", session_name = nil }
  end,
}
package.loaded["pi.statusline"] = { repaint = function() end }
package.loaded["pi.compact_indicator"] = { hide = function() end }

require("pi.config").setup({
  bootstrap = false,
  max_slots = 64,
  slot_min_width = 24,
  slot_min_height = 6,
})
local slots = require("pi.slots")
slots._reset_for_test()

-- Pure layout: solo one id fills like single-slot compute_layout
local solo = slots.compute_layout({
  cols = 100,
  lines = 40,
  chrome = 2,
  ids = { 7 },
  primary = 7,
  margin = 1,
  min_w = 24,
  min_h = 6,
})
h.assert_truthy(solo[7], "solo geo for #7")
h.assert_eq(solo[7].row, 1, "row")
h.assert_eq(solo[7].col, 1, "col")
h.assert_false(solo[1], "no other ids")

h.assert_eq(slots.maximized_id(), nil, "initially nil")

h.assert_truthy(slots.create(), "sat")
local s2 = assert(slots.create())
local id2 = s2.id

h.assert_truthy(slots.maximize_by_id(id2), "maximize ok")
h.assert_eq(slots.maximized_id(), id2, "maximized_id set")
h.assert_eq(slots.primary().id, id2, "primary follows maximize")

local title = slots.format_title(slots.primary())
h.assert_truthy(title:find("✦", 1, true), "title has maximize mark: " .. title)

h.assert_truthy(slots.maximize_restore(), "restore")
h.assert_eq(slots.maximized_id(), nil, "cleared")
h.assert_false(slots.maximize_restore(), "restore noop")

-- same id again while maximized → restore
h.assert_truthy(slots.maximize_by_id(id2), "max again")
h.assert_truthy(slots.maximize_by_id(id2), "same id restores")
h.assert_eq(slots.maximized_id(), nil, "restored by same id")

h.assert_false(slots.maximize_by_id(9999), "missing")

-- close while maximized clears
h.assert_truthy(slots.maximize_by_id(id2), "max for close")
slots.close(id2)
h.assert_eq(slots.maximized_id(), nil, "cleared on close")

-- bare maximize_ask while maximized restores
local s3 = assert(slots.create())
h.assert_truthy(slots.maximize_by_id(s3.id), "max s3")
h.assert_truthy(slots.maximize_ask(), "ask restores when solo")
h.assert_eq(slots.maximized_id(), nil, "ask cleared")

slots._reset_for_test()
print("OK slots_maximize_test")
