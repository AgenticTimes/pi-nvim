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

-- pick_model: list → select → set_model
sent = {}
package.loaded["pi.client"] = {
  is_running = function()
    return true
  end,
  start = function() end,
  send = function(o)
    table.insert(sent, o)
  end,
  request = function(o)
    if o.type == "get_available_models" then
      return {
        success = true,
        data = {
          models = {
            { id = "m-cur", provider = "p", name = "Current" },
            { id = "m-next", provider = "p", name = "Next" },
          },
        },
      }
    end
    if o.type == "get_available_thinking_levels" then
      return { success = true, data = { levels = { "off", "high" } } }
    end
    return { success = false, error = "unexpected " .. tostring(o.type) }
  end,
  set_on_event = function() end,
  stop = function() end,
}
package.loaded["pi.runtime"] = nil
runtime = require("pi.runtime")
session.on_event({
  type = "response",
  command = "set_model",
  data = { id = "m-cur", provider = "p" },
})
local orig_select = vim.ui.select
vim.ui.select = function(items, _opts, cb)
  h.assert_truthy(#items >= 2, "model list")
  -- pick the non-current entry
  local pick = items[2]
  for _, it in ipairs(items) do
    if not tostring(it):find("●", 1, true) then
      pick = it
      break
    end
  end
  cb(pick)
end
runtime.pick_model()
vim.ui.select = orig_select
h.assert_eq(sent[1].type, "set_model", "set_model sent")
h.assert_eq(sent[1].modelId, "m-next", "picked next model")
h.assert_eq(sent[1].provider, "p", "provider")

sent = {}
vim.ui.select = function(items, _opts, cb)
  cb(items[2] or items[1])
end
runtime.pick_thinking()
vim.ui.select = orig_select
h.assert_eq(sent[1].type, "set_thinking_level", "set_thinking sent")
h.assert_eq(sent[1].level, "high", "picked high")

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

session.on_event({
  type = "response",
  command = "set_model",
  data = { id = "m2", provider = "x" },
})
h.assert_eq(session.get().model.id, "m2", "set_model stored")
session.on_event({
  type = "response",
  command = "set_thinking_level",
  data = { level = "low" },
})
h.assert_eq(session.get().thinking, "low", "set_thinking stored")

-- :PiRun path: open UI then prompt
local opened = false
package.loaded["pi.ui"].open = function()
  opened = true
end
sent = {}
runtime.run("hello from run", { open = true })
h.assert_truthy(opened, "run opens ui")
h.assert_eq(sent[1].type, "prompt", "run sends prompt")
h.assert_eq(sent[1].message, "hello from run", "run message")

-- unstub for subsequent tests
package.loaded["pi.client"] = nil
package.loaded["pi.events"] = nil
package.loaded["pi.ui"] = nil
package.loaded["pi.host_tools"] = nil
package.loaded["pi.review"] = nil
package.loaded["pi.session"] = nil
package.loaded["pi.runtime"] = nil
