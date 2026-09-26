local M = {}

local state = {
  status = "idle", -- idle|streaming|compacting
  messages = {},
  touched = {}, ---@type table[]
  model = nil,
  thinking = nil,
  mode = "auto",
  session_name = nil,
  session_file = nil,
  auto_compaction = nil, ---@type boolean|nil
}

function M.reset()
  state.status = "idle"
  state.messages = {}
  state.touched = {}
  state.model = nil
  state.thinking = nil
  state.session_name = nil
  state.session_file = nil
  -- keep mode + auto_compaction preference
  pcall(function()
    require("pi.statusline").stop()
  end)
end

local function sync_busy()
  pcall(function()
    if state.status == "streaming" then
      require("pi.statusline").start("Working")
    elseif state.status == "compacting" then
      require("pi.statusline").start("Compacting")
    else
      require("pi.statusline").stop()
    end
  end)
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
  if data.autoCompactionEnabled ~= nil then
    state.auto_compaction = data.autoCompactionEnabled
  end
  if data.isCompacting then
    state.status = "compacting"
    sync_busy()
  elseif data.isStreaming then
    state.status = "streaming"
    sync_busy()
  elseif data.isStreaming == false and data.isCompacting == false then
    state.status = "idle"
    sync_busy()
  elseif data.isStreaming == false and data.isCompacting == nil then
    state.status = "idle"
    sync_busy()
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
  elseif state.status == "compacting" then
    table.insert(bits, "compact…")
  end
  if state.auto_compaction == false then
    table.insert(bits, "no-autocompact")
  end
  return table.concat(bits, " · ")
end

function M.get()
  return state
end

function M.is_busy()
  return state.status == "streaming" or state.status == "compacting"
end

function M.set_status(s)
  state.status = s
  sync_busy()
end

function M.set_auto_compaction(enabled)
  state.auto_compaction = enabled and true or false
end

function M.touched()
  return state.touched
end

function M.record_edit(entry)
  table.insert(state.touched, entry)
  pcall(function()
    require("pi.statusline").repaint()
  end)
end

function M.remove_touched(idx)
  if idx < 1 or idx > #state.touched then
    return nil
  end
  local removed = table.remove(state.touched, idx)
  pcall(function()
    require("pi.statusline").repaint()
  end)
  pcall(function()
    local buf = require("pi.ui").chat_buf()
    if buf then
      require("pi.render").note_pending_review(buf)
    end
  end)
  return removed
end

function M.on_event(ev)
  if ev.type == "agent_start" then
    state.status = "streaming"
    sync_busy()
  elseif ev.type == "agent_end" then
    if state.status ~= "compacting" then
      state.status = "idle"
      sync_busy()
    end
    pcall(function()
      require("pi.statusline").repaint()
    end)
  elseif ev.type == "compaction_start" then
    state.status = "compacting"
    sync_busy()
  elseif ev.type == "compaction_end" then
    state.status = "idle"
    sync_busy()
    pcall(function()
      require("pi.statusline").repaint()
    end)
  elseif ev.type == "response" and ev.command == "cycle_model" and ev.data then
    state.model = ev.data.model or ev.data
  elseif ev.type == "response" and ev.command == "set_model" and ev.data then
    state.model = ev.data.model or ev.data
  elseif ev.type == "response" and ev.command == "cycle_thinking_level" and ev.data then
    state.thinking = ev.data.level or ev.data
  elseif ev.type == "response" and ev.command == "set_thinking_level" and ev.data then
    state.thinking = ev.data.level or ev.data
  end
end

return M
