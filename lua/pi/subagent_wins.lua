-- Subagent monitor windows: bridge payloads → viewer slots (no extra pi RPC).
local M = {}

---@type table<string, integer> runId → slot id
local by_run = {}
---@type table<integer, any> timer by slot id
local timers = {}

local function enabled()
  local v = require("pi.config").opts.subagent_windows
  return v ~= false
end

local function find_slot(run_id)
  if not run_id or run_id == "" then
    return nil
  end
  local id = by_run[run_id]
  if not id then
    return nil
  end
  local ok, slots = pcall(require, "pi.slots")
  if not ok or type(slots.live) ~= "function" then
    return nil
  end
  for _, s in ipairs(slots.live()) do
    if s.id == id then
      return s
    end
  end
  by_run[run_id] = nil
  return nil
end

local function remap_run(old_id, new_id)
  if not old_id or not new_id or old_id == new_id then
    return
  end
  local slot_id = by_run[old_id]
  if not slot_id then
    return
  end
  by_run[new_id] = slot_id
  by_run[old_id] = nil
  local s = find_slot(new_id)
  if s then
    s.run_id = new_id
  end
end

local function stop_timer(slot_id)
  local t = timers[slot_id]
  if t then
    pcall(function()
      t:stop()
      t:close()
    end)
    timers[slot_id] = nil
  end
end

local function set_lines(buf, lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function append_block(buf, header, body)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- Drop main-chat boilerplate if present
  if lines[1] and lines[1]:match("^# pi chat") then
    local rest = {}
    for i = 2, #lines do
      rest[#rest + 1] = lines[i]
    end
    lines = rest
  end
  if #lines == 1 and lines[1] == "" then
    lines = {}
  end
  if header and header ~= "" then
    lines[#lines + 1] = header
  end
  if body and body ~= "" then
    for _, ln in ipairs(vim.split(body, "\n", { plain = true })) do
      lines[#lines + 1] = ln
    end
  end
  lines[#lines + 1] = ""
  -- Cap buffer growth
  if #lines > 400 then
    local keep = {}
    for i = #lines - 399, #lines do
      keep[#keep + 1] = lines[i]
    end
    lines = keep
    table.insert(lines, 1, "…")
  end
  set_lines(buf, lines)
end

local function read_tail(path, max_bytes)
  if not path or path == "" or vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  max_bytes = max_bytes or 16000
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local size = f:seek("end")
  if not size then
    f:close()
    return nil
  end
  local start = math.max(0, size - max_bytes)
  f:seek("set", start)
  local data = f:read("*a") or ""
  f:close()
  if start > 0 then
    data = "…\n" .. data
  end
  return data
end

local function read_status(dir)
  local raw = read_tail(dir .. "/status.json", 200000)
  if not raw then
    return nil
  end
  local ok, obj = pcall(vim.json.decode, raw:gsub("^…\n", ""))
  if ok and type(obj) == "table" then
    return obj
  end
  return nil
end

--- Prefer *_output.md (pi-subagents) / output-*.log; never dump raw status.json.
local function pick_artifact(dir, hint)
  if type(hint) == "string" and hint ~= "" and vim.fn.filereadable(hint) == 1 then
    return hint
  end
  if not dir or dir == "" then
    return nil
  end
  local st = read_status(dir)
  if st and type(st.outputFile) == "string" and vim.fn.filereadable(st.outputFile) == 1 then
    return st.outputFile
  end
  -- nicobailon pi-subagents: {runId}_{agent}_{i}_output.md
  local out_md = vim.fn.glob(dir .. "/*_output.md", false, true)
  if type(out_md) == "table" and out_md[1] then
    table.sort(out_md)
    return out_md[#out_md]
  end
  local outputs = vim.fn.glob(dir .. "/output-*.log", false, true)
  if type(outputs) == "table" and outputs[1] then
    table.sort(outputs)
    return outputs[#outputs]
  end
  local md = vim.fn.glob(dir .. "/subagent-log-*.md", false, true)
  if type(md) == "table" and md[1] then
    table.sort(md)
    return md[#md]
  end
  for _, name in ipairs({ "output.log", "transcript.jsonl" }) do
    local p = dir .. "/" .. name
    if vim.fn.filereadable(p) == 1 then
      return p
    end
  end
  return nil
end

local function clean_goal(goal, agent)
  goal = tostring(goal or "")
  if goal == "" or goal:find("redacted", 1, true) or goal == "[prompt redacted]" then
    return agent or "subagent"
  end
  return goal
end

local function refresh_from_disk(slot)
  if not slot or (not slot.async_dir and not slot.output_path) then
    return
  end
  local st = slot.async_dir and read_status(slot.async_dir) or nil
  if st and st.state then
    if st.state == "complete" or st.state == "failed" or st.state == "stopped" then
      slot.status = "idle"
      slot.activity = st.state == "complete" and "done" or st.state
    else
      slot.status = "busy"
      slot.activity = tostring(st.state)
    end
  end
  local path = pick_artifact(slot.async_dir, slot.output_path)
  slot.artifact_path = path
  local text = path and read_tail(path) or nil
  local header = string.format("── %s · %s ──", slot.agent or "subagent", tostring(slot.run_id or "?"):sub(1, 8))
  if st and st.state then
    header = header .. string.format(" · %s", st.state)
  end
  if not text or text == "" then
    text = "(waiting for output…)"
  end
  set_lines(slot.chat_buf, vim.split(header .. "\n" .. text, "\n", { plain = true }))
  require("pi.slots").refresh_titles()
end

local function ensure_timer(slot)
  if not slot or timers[slot.id] then
    return
  end
  if not slot.async_dir and not slot.output_path then
    return
  end
  local t = vim.uv.new_timer()
  if not t then
    return
  end
  timers[slot.id] = t
  t:start(600, 1000, function()
    vim.schedule(function()
      local s = find_slot(slot.run_id)
      if not s then
        stop_timer(slot.id)
        return
      end
      refresh_from_disk(s)
      if s.status == "idle" then
        stop_timer(slot.id)
      end
    end)
  end)
end

local function schedule_close(run_id, ms)
  vim.defer_fn(function()
    local s = find_slot(run_id)
    if s and s.status == "idle" then
      require("pi.slots").close(s.id)
      by_run[run_id] = nil
    end
  end, ms)
end

---@param payload table
function M.handle(payload)
  if not enabled() or type(payload) ~= "table" then
    return false
  end
  local op = payload.op
  local run_id = tostring(payload.runId or payload.toolCallId or "")
  local tool_call_id = payload.toolCallId and tostring(payload.toolCallId) or nil
  if run_id == "" then
    return false
  end

  -- Merge toolCallId window → real async runId
  if tool_call_id and tool_call_id ~= run_id and by_run[tool_call_id] then
    remap_run(tool_call_id, run_id)
  end

  if op == "started" then
    local existing = find_slot(run_id) or (tool_call_id and find_slot(tool_call_id)) or nil
    local label = tostring(payload.agent or payload.label or "subagent")
    local goal = clean_goal(payload.goal or payload.task, label)
    if existing then
      existing.status = "busy"
      existing.activity = payload.phase or "running"
      existing.agent = label
      existing.goal = goal
      existing.run_id = run_id
      by_run[run_id] = existing.id
      if payload.asyncDir then
        existing.async_dir = tostring(payload.asyncDir)
        ensure_timer(existing)
        refresh_from_disk(existing)
      end
      if payload.outputPath then
        existing.output_path = tostring(payload.outputPath)
        refresh_from_disk(existing)
      end
      require("pi.slots").refresh_titles()
      return true
    end
    local slot, err = require("pi.slots").create_viewer({
      run_id = run_id,
      agent = label,
      goal = goal,
      async_dir = payload.asyncDir and tostring(payload.asyncDir) or nil,
    })
    if type(slot) ~= "table" then
      require("pi.notify").soft_notify("subagent window: " .. tostring(err or slot or "failed"), vim.log.levels.WARN)
      return false
    end
    by_run[run_id] = slot.id
    if payload.outputPath then
      slot.output_path = tostring(payload.outputPath)
    end
    append_block(slot.chat_buf, string.format("● %s started", label), goal ~= label and goal or nil)
    if slot.async_dir or slot.output_path then
      ensure_timer(slot)
      refresh_from_disk(slot)
    end
    return true
  end

  local slot = find_slot(run_id)
  if not slot and payload.parentRunId then
    slot = find_slot(tostring(payload.parentRunId))
  end
  if not slot and tool_call_id then
    slot = find_slot(tool_call_id)
  end

  if not slot then
    if op == "complete" then
      -- Failed fast (unknown agent): short-lived viewer or skip if tiny
      local label = tostring(payload.agent or payload.label or "subagent")
      local summary = tostring(payload.summary or "")
      if payload.failedFast or summary:find("Unknown agent:", 1, true) then
        require("pi.notify").soft_notify(
          (summary:match("Unknown agent:[^\n]+") or "subagent failed"):sub(1, 120),
          vim.log.levels.WARN
        )
        return true
      end
      local s, err = require("pi.slots").create_viewer({
        run_id = run_id,
        agent = label,
        goal = clean_goal(nil, label),
        async_dir = payload.asyncDir and tostring(payload.asyncDir) or nil,
      })
      if not s then
        require("pi.notify").soft_notify("subagent window: " .. tostring(err or "failed"), vim.log.levels.WARN)
        return false
      end
      by_run[run_id] = s.id
      slot = s
    else
      return false
    end
  end

  if op == "status" then
    slot.status = "busy"
    slot.activity = tostring(payload.phase or payload.status or "running")
    if payload.asyncDir then
      slot.async_dir = tostring(payload.asyncDir)
      ensure_timer(slot)
    end
    if payload.outputPath then
      slot.output_path = tostring(payload.outputPath)
    end
    local text = tostring(payload.text or "")
    -- Skip JSON envelopes / capability dumps
    if text ~= ""
      and not text:find("async run is detached", 1, true)
      and not text:find("launchContractDigest", 1, true)
      and not text:find("Executable agents", 1, true)
      and not text:match("^%s*{")
      and #text < 500
    then
      append_block(slot.chat_buf, "· update", text:sub(1, 400))
    elseif slot.async_dir or slot.output_path then
      refresh_from_disk(slot)
    end
    require("pi.slots").refresh_titles()
    return true
  end

  if op == "complete" then
    slot.status = "idle"
    slot.activity = payload.success == false and "failed" or "done"
    stop_timer(slot.id)
    if payload.asyncDir then
      slot.async_dir = tostring(payload.asyncDir)
    end
    if payload.outputPath then
      slot.output_path = tostring(payload.outputPath)
    end
    local summary = tostring(payload.summary or "")
    if summary:find("launchContractDigest", 1, true)
      or summary:find("Executable agents", 1, true)
      or summary:match("^%s*{")
    then
      summary = ""
    end
    -- Prefer disk output over spawn-receipt text
    if slot.async_dir or slot.output_path then
      refresh_from_disk(slot)
      local path = pick_artifact(slot.async_dir, slot.output_path)
      local out = path and read_tail(path, 8000)
      if out and out ~= "" and not out:find("async run is detached", 1, true) then
        summary = out
      end
    end
    if summary:find("async run is detached", 1, true) or summary:find("native completion notification", 1, true) then
      summary = "(still running in background…)"
      slot.status = "busy"
      slot.activity = "running"
      if slot.async_dir then
        ensure_timer(slot)
      end
      require("pi.slots").refresh_titles()
      return true
    end
    if summary ~= "" then
      append_block(
        slot.chat_buf,
        payload.success == false and "✗ failed" or "✓ done",
        summary:sub(1, 6000)
      )
    else
      append_block(slot.chat_buf, payload.success == false and "✗ failed" or "✓ done", nil)
    end
    require("pi.slots").refresh_titles()
    local cfg = require("pi.config").opts
    local fail_fast = payload.failedFast or summary:find("Unknown agent:", 1, true)
    if fail_fast then
      schedule_close(run_id, 2500)
    elseif cfg.subagent_window_autoclose then
      schedule_close(run_id, tonumber(cfg.subagent_window_autoclose_ms) or 8000)
    end
    return true
  end

  return false
end

function M.handle_ui_request(req)
  if not req or (req.method ~= "setWidget" and req.method ~= "set_widget") then
    return false
  end
  local key = req.widgetKey or req.key
  if key ~= "__nvim_subagent__" then
    return false
  end
  local lines = req.widgetLines or req.lines
  if type(lines) ~= "table" or not lines[1] then
    return true
  end
  local ok, payload = pcall(vim.json.decode, lines[1])
  if not ok or type(payload) ~= "table" then
    return true
  end
  -- Sync: caller is already on main thread (RPC event). Avoid deferred
  -- handle after tests/modules swap package.loaded["pi.slots"].
  M.handle(payload)
  return true
end

function M._reset_for_test()
  for id, _ in pairs(timers) do
    stop_timer(id)
  end
  by_run = {}
end

return M
