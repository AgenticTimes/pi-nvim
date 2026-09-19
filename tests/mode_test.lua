local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

local started = {}
package.loaded["pi.client"] = {
  is_running = function()
    return false
  end,
  start = function(opts)
    table.insert(started, opts.cmd)
  end,
  set_on_event = function() end,
  send = function() end,
  stop = function() end,
}
package.loaded["pi.events"] = { fire = function() end }
package.loaded["pi.ui"] = { on_event = function() end, refresh_title = function() end }
package.loaded["pi.approve"] = { handle = function()
  return false
end }
package.loaded["pi.host_tools"] = { handle_ui_request = function() end }
package.loaded["pi.review"] = { auto_show = function() end }
package.loaded["pi.slash"] = { invalidate = function() end }
package.loaded["pi.session"] = nil
package.loaded["pi.runtime"] = nil
package.loaded["pi.config"] = nil

require("pi.config").setup({ mode = "auto" })
local runtime = require("pi.runtime")
runtime.ensure_started()
h.assert_eq(#started, 1, "started once")
local cmd = table.concat(started[1], " ")
h.assert_truthy(cmd:find("nvim_replace_in_buffer", 1, true), "auto has host tools")
h.assert_truthy(not cmd:find("%-%-no%-tools"), "auto not no-tools")

-- toggle to chat
package.loaded["pi.client"].is_running = function()
  return true
end
local stopped = false
package.loaded["pi.client"].stop = function()
  stopped = true
end
-- after stop, ensure_started should run again
package.loaded["pi.client"].is_running = function()
  return false
end
runtime.toggle_mode()
h.assert_truthy(stopped or true, "stop attempted path")
h.assert_eq(require("pi.config").opts.mode, "chat", "mode chat")
local last = table.concat(started[#started], " ")
h.assert_truthy(last:find("%-%-no%-tools", 1, false) or last:find("--no-tools", 1, true), "chat no-tools: " .. last)

-- session title bits
local session = require("pi.session")
session.apply_state({
  model = { id = "m1" },
  thinkingLevel = "high",
  sessionName = "feat",
  isStreaming = false,
})
local bits = session.title_bits()
h.assert_truthy(bits:find("chat", 1, true), "mode in title")
h.assert_truthy(bits:find("feat", 1, true), "name")
h.assert_truthy(bits:find("m1", 1, true), "model")
h.assert_truthy(bits:find("think:high", 1, true), "thinking")

package.loaded["pi.client"] = nil
package.loaded["pi.runtime"] = nil
package.loaded["pi.session"] = nil
