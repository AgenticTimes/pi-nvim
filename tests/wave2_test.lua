local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

-- Capture outbound RPC payloads
local sent = {}
package.loaded["pi.client"] = {
  is_running = function()
    return true
  end,
  start = function() end,
  set_on_event = function() end,
  send = function(msg)
    table.insert(sent, msg)
  end,
  stop = function() end,
}

package.loaded["pi.events"] = { fire = function() end }
package.loaded["pi.ui"] = {
  on_event = function() end,
  chat_buf = function()
    return nil
  end,
}
package.loaded["pi.host_tools"] = { handle_ui_request = function() end }
package.loaded["pi.review"] = { auto_show = function() end }

-- fresh session/runtime
package.loaded["pi.session"] = nil
package.loaded["pi.runtime"] = nil
package.loaded["pi.config"] = nil

local session = require("pi.session")
local runtime = require("pi.runtime")
local config = require("pi.config")

-- idle prompt: no streamingBehavior
sent = {}
session.set_status("idle")
runtime.prompt("hello idle")
h.assert_eq(#sent, 1, "idle send count")
h.assert_eq(sent[1].type, "prompt", "idle type")
h.assert_eq(sent[1].message, "hello idle", "idle msg")
h.assert_eq(sent[1].streamingBehavior, nil, "idle no stream behavior")

-- busy prompt: default busy_submit = steer
sent = {}
session.set_status("streaming")
runtime.prompt("steer me")
h.assert_eq(sent[1].streamingBehavior, "steer", "busy default steer")

-- busy with followUp override
sent = {}
runtime.prompt("later", { streamingBehavior = "followUp" })
h.assert_eq(sent[1].streamingBehavior, "followUp", "busy followUp")

-- config override
sent = {}
config.setup({ busy_submit = "followUp" })
runtime.prompt("cfg")
h.assert_eq(sent[1].streamingBehavior, "followUp", "config busy_submit")
config.setup({ busy_submit = "steer" })

-- dedicated steer / follow_up / cycle
sent = {}
runtime.steer("redirect")
h.assert_eq(sent[1].type, "steer", "steer cmd")
sent = {}
runtime.follow_up("after")
h.assert_eq(sent[1].type, "follow_up", "follow_up cmd")
sent = {}
runtime.cycle_model()
h.assert_eq(sent[1].type, "cycle_model", "cycle_model")
sent = {}
runtime.cycle_thinking()
h.assert_eq(sent[1].type, "cycle_thinking_level", "cycle_thinking")

-- session stores model/thinking from responses
session.on_event({
  type = "response",
  command = "cycle_model",
  data = { model = { id = "m1" }, thinkingLevel = "high" },
})
h.assert_eq(session.get().model.id, "m1", "model stored")
session.on_event({
  type = "response",
  command = "cycle_thinking_level",
  data = { level = "medium" },
})
h.assert_eq(session.get().thinking, "medium", "thinking stored")

-- unstub for subsequent tests
package.loaded["pi.client"] = nil
package.loaded["pi.events"] = nil
package.loaded["pi.ui"] = nil
package.loaded["pi.host_tools"] = nil
package.loaded["pi.review"] = nil
package.loaded["pi.session"] = nil
package.loaded["pi.runtime"] = nil
