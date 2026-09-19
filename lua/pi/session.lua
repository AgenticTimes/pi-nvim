local M = {}

local state = {
  status = "idle", -- idle|streaming
  messages = {},
  touched = {}, ---@type table[]
  model = nil,
  thinking = nil,
  mode = "auto",
  session_name = nil,
  session_file = nil,
}

function M.reset()
  state.status = "idle"
  state.messages = {}
  state.touched = {}
  state.model = nil
  state.thinking = nil
  state.session_name = nil
  state.session_file = nil
  -- keep mode
end

function M.apply_state(data)
  if type(data) ~= "table" then
    return
  end
  if data.model then
    state.model = data.model
  end
  if data.thinkingLevel then
    state.thinking = data.thinkingLevel
  end
  if data.sessionName then
    state.session_name = data.sessionName
  end
  if data.sessionFile then
    state.session_file = data.sessionFile
  end
  if data.isStreaming then
    state.status = "streaming"
  elseif data.isStreaming == false then
    state.status = "idle"
  end
end

function M.title_bits()
  local bits = {}
  local mode = require("pi.config").opts.mode or state.mode or "auto"
  table.insert(bits, mode)
  if state.session_name and state.session_name ~= "" then
    table.insert(bits, state.session_name)
  end
  if type(state.model) == "table" and state.model.id then
    table.insert(bits, state.model.id)
  elseif type(state.model) == "string" then
    table.insert(bits, state.model)
  end
  if state.thinking then
    table.insert(bits, "think:" .. tostring(state.thinking))
  end
  if state.status == "streaming" then
    table.insert(bits, "…")
  end
  return table.concat(bits, " · ")
end

function M.get()
  return state
end

function M.is_busy()
  return state.status == "streaming"
end

function M.set_status(s)
  state.status = s
end

function M.touched()
  return state.touched
end

function M.record_edit(entry)
  table.insert(state.touched, entry)
end

function M.remove_touched(idx)
  if idx < 1 or idx > #state.touched then
    return nil
  end
  return table.remove(state.touched, idx)
end

function M.on_event(ev)
  if ev.type == "agent_start" then
    state.status = "streaming"
  elseif ev.type == "agent_end" then
    state.status = "idle"
  elseif ev.type == "response" and ev.command == "cycle_model" and ev.data then
    state.model = ev.data.model or ev.data
  elseif ev.type == "response" and ev.command == "cycle_thinking_level" and ev.data then
    state.thinking = ev.data.level or ev.data
  end
end

return M
