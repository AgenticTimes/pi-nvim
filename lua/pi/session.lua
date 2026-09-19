local M = {}

local state = {
  status = "idle", -- idle|streaming
  messages = {},
  touched = {}, ---@type table[]
}

function M.reset()
  state.status = "idle"
  state.messages = {}
  state.touched = {}
end

function M.get()
  return state
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
  end
end

return M
