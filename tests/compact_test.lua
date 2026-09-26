local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

local sent = {}
local running = false
package.loaded["pi.client"] = {
  is_running = function()
    return running
  end,
  send = function(obj)
    table.insert(sent, obj)
  end,
  start = function(opts)
    running = true
    _G.__pi_on_event = opts and opts.on_event
    return 1
  end,
  set_on_event = function(cb)
    _G.__pi_on_event = cb
  end,
  stop = function()
    running = false
  end,
  request = function()
    return { success = true, data = {} }
  end,
}
package.loaded["pi.statusline"] = {
  start = function(label)
    _G.__pi_busy_label = label
  end,
  stop = function()
    _G.__pi_busy_label = nil
  end,
  repaint = function() end,
}
_G.__pi_chat_lines = {}
package.loaded["pi.ui"] = {
  on_event = function() end,
  refresh_title = function() end,
  chat_buf = function()
    return 1
  end,
  focus_chat = function() end,
}
package.loaded["pi.render"] = {
  append = function(_, line)
    table.insert(_G.__pi_chat_lines, line)
  end,
  normalize_messages = function()
    return {}
  end,
  hydrate = function()
    return 0
  end,
  reset = function() end,
}
package.loaded["pi.events"] = { fire = function() end }
package.loaded["pi.approve"] = {
  handle = function()
    return false
  end,
  reset_sticky = function() end,
}
package.loaded["pi.host_tools"] = { handle_ui_request = function() end }
package.loaded["pi.review"] = { auto_show = function() end }
package.loaded["pi.slash"] = { invalidate = function() end }
package.loaded["pi.sessions"] = {
  latest_for_cwd = function()
    return nil
  end,
}
package.loaded["pi.session"] = nil
package.loaded["pi.runtime"] = nil
package.loaded["pi.config"] = nil
package.loaded["pi"] = nil

require("pi.config").setup({ resume_last = false })
local runtime = require("pi.runtime")

-- Force start without depending on real `pi` binary
runtime.ensure_started({
  no_resume = true,
  cmd = { "sleep", "60" },
})
h.assert_truthy(running, "client started")
h.assert_truthy(_G.__pi_on_event, "on_event hooked")

sent = {}
runtime.compact({ custom_instructions = "Focus on code" })
h.assert_eq(sent[1].type, "compact", "compact RPC")
h.assert_eq(sent[1].customInstructions, "Focus on code", "instructions")
h.assert_eq(require("pi.session").get().status, "compacting", "status compacting")
h.assert_eq(_G.__pi_busy_label, "Compacting", "statusline Compacting")

sent = {}
runtime.set_auto_compaction(false)
h.assert_eq(sent[1].type, "set_auto_compaction", "set_auto_compaction RPC")
h.assert_eq(sent[1].enabled, false, "enabled false")
h.assert_eq(require("pi.session").get().auto_compaction, false, "local auto off")

_G.__pi_chat_lines = {}
_G.__pi_on_event({
  type = "compaction_end",
  reason = "manual",
  result = { tokensBefore = 150000, estimatedTokensAfter = 32000 },
  aborted = false,
})
vim.wait(80)
h.assert_eq(require("pi.session").get().status, "idle", "idle after compaction_end")
h.assert_truthy(#_G.__pi_chat_lines > 0, "chat line appended")
h.assert_truthy(_G.__pi_chat_lines[#_G.__pi_chat_lines]:find("150k"), "shows before tokens")

-- cleanup job
package.loaded["pi.client"].stop()
package.loaded["pi.render"] = nil
package.loaded["pi.ui"] = nil
package.loaded["pi.runtime"] = nil
print("OK compact_test")
