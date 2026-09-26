local M = {}

local function extension_path()
  return require("pi.config").root() .. "/extensions/nvim_host_tools.ts"
end

--- Soft preference only: pi has no tool-priority API. Excluding disk edit/write
--- steers mutations through nvim_* so Accept/Reject still works.
local DEFAULT_EXCLUDE = "edit,write"

local resume_scheduled = false
local hydrate_opts ---@type table|nil
local pending_hydrate_path ---@type string|nil
local skip_switch_hydrate = false
local HYDRATE_ID = "hydrate-msgs"

local function apply_hydrate(data, opts)
  opts = opts or {}
  local render = require("pi.render")
  local messages = render.normalize_messages(data or {})
  local chat = require("pi.ui").chat_buf()
  local n = render.hydrate(chat, messages, opts)
  pcall(function()
    require("pi.ui").refresh_title()
  end)
  if n > 0 then
    vim.notify(string.format("pi: loaded %d message(s)", n), vim.log.levels.INFO)
  else
    vim.notify("pi: session switched but no messages to show", vim.log.levels.WARN)
  end
  return n
end

--- Prefer disk jsonl (reliable); RPC get_messages is fallback for huge/partial cases
local function hydrate_from_path(path, opts)
  if not path or path == "" then
    return false
  end
  local sessions = require("pi.sessions")
  local hist = sessions.open_history(path)
  local msgs, exhausted = sessions.history_page(hist)
  if #msgs == 0 then
    return false
  end
  local footer
  if exhausted then
    footer = (opts and opts.footer) or "· resumed session"
  else
    footer = "· 往上滚查看更早"
  end
  opts = vim.tbl_extend("force", opts or {}, {
    history = exhausted and nil or hist,
    footer = footer,
  })
  apply_hydrate({ messages = msgs }, opts)
  return true
end

local function on_event(ev)
  require("pi.session").on_event(ev)
  require("pi.events").fire(ev)
  pcall(function()
    require("pi.ui").on_event(ev)
  end)

  if ev.type == "extension_ui_request" then
    if require("pi.approve").handle(ev) then
      return
    end
    local resp = require("pi.host_tools").handle_ui_request(ev)
    if resp then
      require("pi.client").send(resp)
      require("pi.review").auto_show()
    end
  end

  if ev.type == "response" and ev.success and (ev.command == "cycle_model" or ev.command == "cycle_thinking_level") then
    pcall(function()
      local render = require("pi.render")
      local chat = require("pi.ui").chat_buf()
      render.append(chat, string.format("· %s → %s", ev.command, vim.inspect(ev.data):gsub("%s+", " "):sub(1, 120)))
      require("pi.ui").refresh_title()
    end)
  end

  if ev.type == "response" and ev.command == "set_model" then
    if ev.success then
      local m = ev.data and (ev.data.model or ev.data) or {}
      local label = (m.provider and m.id) and (m.provider .. "/" .. m.id) or vim.inspect(m):sub(1, 80)
      vim.schedule(function()
        vim.notify("pi: model → " .. label, vim.log.levels.INFO)
        pcall(function()
          require("pi.ui").refresh_title()
        end)
      end)
    else
      vim.schedule(function()
        vim.notify("pi: set_model failed: " .. tostring(ev.error or "?"), vim.log.levels.ERROR)
      end)
    end
  end

  if ev.type == "response" and ev.command == "set_thinking_level" then
    if ev.success then
      local level = ev.data and (ev.data.level or ev.data) or "?"
      vim.schedule(function()
        vim.notify("pi: thinking → " .. tostring(level), vim.log.levels.INFO)
        pcall(function()
          require("pi.ui").refresh_title()
        end)
      end)
    else
      vim.schedule(function()
        vim.notify("pi: set_thinking_level failed: " .. tostring(ev.error or "?"), vim.log.levels.ERROR)
      end)
    end
  end

  -- Async hydrate via RPC (fallback only)
  if ev.type == "response" and ev.id == HYDRATE_ID then
    local opts = hydrate_opts or { footer = "· resumed session" }
    hydrate_opts = nil
    if ev.success then
      vim.schedule(function()
        apply_hydrate(ev.data, opts)
      end)
    else
      vim.schedule(function()
        vim.notify("pi: hydrate failed: " .. tostring(ev.error or "unknown"), vim.log.levels.WARN)
      end)
    end
    return
  end

  if ev.type == "response" and ev.command == "switch_session" then
    local path = pending_hydrate_path
    local skip = skip_switch_hydrate
    pending_hydrate_path = nil
    skip_switch_hydrate = false
    if not ev.success or (ev.data and ev.data.cancelled) then
      vim.schedule(function()
        vim.notify("pi: switch_session failed: " .. tostring(ev.error or "cancelled"), vim.log.levels.WARN)
      end)
      return
    end
    vim.schedule(function()
      require("pi.slash").invalidate()
      -- Disk paint already happened; get_messages would decode the whole
      -- session on the main thread and lock input.
      if skip then
        M.refresh_state()
        pcall(function()
          require("pi.ui").focus_chat()
        end)
        return
      end
      local opts = { footer = "· resumed session" }
      if path then
        hydrate_from_path(path, opts)
        M.refresh_state()
        return
      end
      M.hydrate_chat(opts)
      M.refresh_state()
    end)
  end

  if ev.type == "response" and ev.command == "get_state" and ev.success and ev.data then
    require("pi.session").apply_state(ev.data)
    pcall(function()
      require("pi.ui").refresh_title()
    end)
  end

  if ev.type == "response" and ev.command == "set_session_name" and ev.success then
    pcall(function()
      M.refresh_state()
    end)
  end

  if ev.type == "response" and ev.command == "export_html" and ev.success then
    local path = ev.data and ev.data.path
    vim.notify("pi: exported HTML" .. (path and (": " .. path) or ""), vim.log.levels.INFO)
  end
end

local function build_cmd(opts)
  opts = opts or {}
  local config = require("pi.config")
  local exe = config.opts.executable or "pi"
  local ext = extension_path()
  local mode = opts.mode or config.opts.mode or "auto"
  local cmd = {
    exe,
    "--mode",
    "rpc",
    "--no-extensions",
  }
  if mode == "chat" then
    table.insert(cmd, "--no-tools")
  else
    -- Builtins (bash/read/grep/…) on; host extension registers nvim_*.
    -- No --tools allowlist (that would hide builtins). Optional exclude list
    -- is the only “prefer nvim for edits” knob pi exposes.
    vim.list_extend(cmd, { "-e", ext })
    local exclude = config.opts.tools_exclude
    if exclude == nil then
      exclude = DEFAULT_EXCLUDE
    end
    if type(exclude) == "table" then
      exclude = table.concat(exclude, ",")
    end
    if type(exclude) == "string" and exclude ~= "" then
      vim.list_extend(cmd, { "--exclude-tools", exclude })
    end
  end
  if opts.no_session then
    table.insert(cmd, "--no-session")
  end
  return cmd
end

--- Fire-and-forget get_messages → paint chat (never blocks UI)
function M.hydrate_chat(opts)
  opts = opts or {}
  local client = require("pi.client")
  if not client.is_running() then
    return
  end
  hydrate_opts = opts
  client.send({ type = "get_messages", id = HYDRATE_ID })
end

local function schedule_resume(cwd)
  if resume_scheduled then
    return
  end
  local config = require("pi.config")
  if config.opts.resume_last == false then
    return
  end
  resume_scheduled = true
  vim.defer_fn(function()
    resume_scheduled = false
    if not require("pi.client").is_running() then
      return
    end
    local latest = require("pi.sessions").latest(cwd)
    if not latest then
      return
    end
    -- UI immediately from the tail of the file. switch_session must not
    -- paint again, and must not fall through to get_messages.
    hydrate_from_path(latest.path, { footer = "· resumed session" })
    local cur = require("pi.session").get().session_file
    if cur and cur == latest.path then
      return
    end
    M.switch_session(latest.path, { skip_hydrate = true })
  end, 200)
end

function M.ensure_started(opts)
  opts = opts or {}
  local client = require("pi.client")
  if client.is_running() then
    return
  end
  local cwd = opts.cwd or vim.fn.getcwd()
  local cmd = opts.cmd or build_cmd(opts)
  client.start({
    cmd = cmd,
    cwd = cwd,
    on_event = on_event,
  })
  client.set_on_event(on_event)
  vim.defer_fn(function()
    M.refresh_state()
  end, 100)
  if not opts.no_resume then
    schedule_resume(cwd)
  elseif opts.resume_path and opts.resume_path ~= "" then
    vim.defer_fn(function()
      if require("pi.client").is_running() then
        M.switch_session(opts.resume_path)
      end
    end, 200)
  end
end

function M.refresh_state()
  local client = require("pi.client")
  if not client.is_running() then
    return
  end
  client.send({ type = "get_state", id = "get-state" })
end

function M.prompt(message, opts)
  opts = opts or {}
  M.ensure_started()
  local session = require("pi.session")
  local payload = { type = "prompt", message = message }
  if session.is_busy() then
    local mode = opts.streamingBehavior or require("pi.config").opts.busy_submit or "steer"
    payload.streamingBehavior = mode
  elseif opts.streamingBehavior then
    payload.streamingBehavior = opts.streamingBehavior
  end
  require("pi.client").send(payload)
  -- Optimistic busy: agent_start can lag; keep statusline visible immediately.
  if not session.is_busy() then
    session.set_status("streaming")
  end
end

function M.run(message, opts)
  opts = opts or {}
  if opts.open ~= false then
    require("pi.ui").open()
  end
  M.prompt(message, opts)
end

function M.steer(message)
  M.ensure_started()
  require("pi.client").send({ type = "steer", message = message })
end

function M.follow_up(message)
  M.ensure_started()
  require("pi.client").send({ type = "follow_up", message = message })
end

--- Abort in-flight LLM turn (+ bash tools). Does not kill the RPC job.
---@return boolean sent true if abort RPC was delivered
function M.abort()
  local client = require("pi.client")
  local sent = false
  if client.is_running() then
    -- abort: cancel LLM stream; abort_bash: kill in-flight shell tools
    client.send({ type = "abort" })
    pcall(function()
      client.send({ type = "abort_bash" })
    end)
    sent = true
  end
  require("pi.session").set_status("idle")
  pcall(function()
    require("pi.statusline").stop()
  end)
  if sent then
    vim.notify("pi: interrupted", vim.log.levels.INFO)
  else
    vim.notify("pi: interrupt ignored (RPC not running)", vim.log.levels.WARN)
  end
  return sent
end

--- Public alias of `abort`.
M.interrupt = M.abort

function M.new_session()
  M.ensure_started({ no_resume = true })
  require("pi.client").send({ type = "new_session" })
  require("pi.session").reset()
  require("pi.slash").invalidate()
  require("pi.approve").reset_sticky()
  pcall(function()
    require("pi.render").reset(require("pi.ui").chat_buf())
  end)
  vim.defer_fn(function()
    M.refresh_state()
  end, 100)
end

function M.switch_session(session_path, opts)
  opts = opts or {}
  M.ensure_started({ no_resume = true })
  skip_switch_hydrate = opts.skip_hydrate == true
  if not opts.skip_hydrate then
    pending_hydrate_path = session_path
  else
    pending_hydrate_path = nil
  end
  require("pi.client").send({ type = "switch_session", sessionPath = session_path, id = "switch-session" })
  require("pi.session").reset()
  vim.notify("pi: switching session…", vim.log.levels.INFO)
end

function M.set_session_name(name)
  M.ensure_started()
  if not name or name == "" then
    vim.ui.input({ prompt = "pi session name: " }, function(n)
      if n and n ~= "" then
        require("pi.client").send({ type = "set_session_name", name = n, id = "set-name" })
      end
    end)
    return
  end
  require("pi.client").send({ type = "set_session_name", name = name, id = "set-name" })
end

function M.cycle_model()
  M.ensure_started()
  require("pi.client").send({ type = "cycle_model", id = "cycle-model" })
  vim.notify("pi: cycling model…", vim.log.levels.INFO)
end

function M.cycle_thinking()
  M.ensure_started()
  require("pi.client").send({ type = "cycle_thinking_level", id = "cycle-think" })
  vim.notify("pi: cycling thinking…", vim.log.levels.INFO)
end

local function model_label(m)
  local prov = m.provider or "?"
  local id = m.id or "?"
  local name = m.name
  if name and name ~= "" and name ~= id then
    return string.format("%s/%s  · %s", prov, id, name)
  end
  return string.format("%s/%s", prov, id)
end

--- Fuzzy-pick a model (get_available_models → vim.ui.select → set_model)
function M.pick_model()
  M.ensure_started()
  local client = require("pi.client")
  local resp, err = client.request({ type = "get_available_models", id = "get-models" }, 15000)
  if not resp or not resp.success then
    vim.notify("pi: get_available_models failed: " .. tostring(err or (resp and resp.error) or "?"), vim.log.levels.ERROR)
    return
  end
  local models = (resp.data and resp.data.models) or {}
  if #models == 0 then
    vim.notify("pi: no models available", vim.log.levels.WARN)
    return
  end

  local cur = require("pi.session").get().model
  local cur_id = type(cur) == "table" and cur.id or cur
  local cur_prov = type(cur) == "table" and cur.provider or nil

  table.sort(models, function(a, b)
    local ac = a.id == cur_id and (not cur_prov or a.provider == cur_prov)
    local bc = b.id == cur_id and (not cur_prov or b.provider == cur_prov)
    if ac ~= bc then
      return ac
    end
    if tostring(a.provider) ~= tostring(b.provider) then
      return tostring(a.provider) < tostring(b.provider)
    end
    return tostring(a.id) < tostring(b.id)
  end)

  local labels = {}
  local by_label = {}
  for _, m in ipairs(models) do
    local label = model_label(m)
    if m.id == cur_id and (not cur_prov or m.provider == cur_prov) then
      label = "● " .. label
    end
    -- disambiguate duplicate labels
    if by_label[label] then
      label = label .. " #" .. tostring(#labels + 1)
    end
    table.insert(labels, label)
    by_label[label] = m
  end

  vim.ui.select(labels, { prompt = "pi model" }, function(item)
    if not item then
      return
    end
    local m = by_label[item]
    if not m or not m.id or not m.provider then
      vim.notify("pi: invalid model selection", vim.log.levels.WARN)
      return
    end
    client.send({
      type = "set_model",
      provider = m.provider,
      modelId = m.id,
      id = "set-model",
    })
  end)
end

--- Fuzzy-pick thinking level for current model
function M.pick_thinking()
  M.ensure_started()
  local client = require("pi.client")
  local resp, err = client.request({ type = "get_available_thinking_levels", id = "get-think" }, 10000)
  if not resp or not resp.success then
    vim.notify("pi: get_available_thinking_levels failed: " .. tostring(err or (resp and resp.error) or "?"), vim.log.levels.ERROR)
    return
  end
  local levels = (resp.data and resp.data.levels) or resp.data or {}
  if type(levels) ~= "table" or #levels == 0 then
    vim.notify("pi: no thinking levels for this model", vim.log.levels.WARN)
    return
  end

  local cur = require("pi.session").get().thinking
  local labels = {}
  for _, lv in ipairs(levels) do
    local s = tostring(lv)
    if cur and tostring(cur) == s then
      s = "● " .. s
    end
    table.insert(labels, s)
  end

  vim.ui.select(labels, { prompt = "pi thinking" }, function(item)
    if not item then
      return
    end
    local level = item:gsub("^●%s*", "")
    client.send({
      type = "set_thinking_level",
      level = level,
      id = "set-think",
    })
  end)
end

--- Toggle chat (no tools) vs auto (host tools). Restarts RPC job.
function M.set_mode(mode)
  if mode ~= "chat" and mode ~= "auto" then
    error("pi mode must be chat|auto")
  end
  local config = require("pi.config")
  config.opts.mode = mode
  require("pi.session").get().mode = mode
  local session_file = require("pi.session").get().session_file
  local client = require("pi.client")
  if client.is_running() then
    client.stop()
  end
  M.ensure_started({
    mode = mode,
    no_resume = true,
    resume_path = session_file,
  })
  vim.notify("pi: mode → " .. mode, vim.log.levels.INFO)
  pcall(function()
    require("pi.ui").refresh_title()
  end)
end

function M.toggle_mode()
  local cur = require("pi.config").opts.mode or "auto"
  M.set_mode(cur == "chat" and "auto" or "chat")
end

function M.export_html(output_path, opts)
  opts = opts or {}
  M.ensure_started()
  local client = require("pi.client")
  local payload = { type = "export_html" }
  if output_path and output_path ~= "" then
    payload.outputPath = output_path
  end
  local resp, err = client.request(payload, require("pi.config").opts.rpc_timeout * 1000)
  if not resp or not resp.success then
    -- fallback fire-and-forget if request times out / no id path
    client.send(vim.tbl_extend("force", payload, { id = "export-html" }))
    vim.notify("pi: exporting HTML… (" .. tostring(err or "async") .. ")", vim.log.levels.INFO)
    return
  end
  local path = resp.data and resp.data.path
  vim.notify("pi: exported HTML" .. (path and (": " .. path) or ""), vim.log.levels.INFO)
  if path and (opts.open ~= false) and require("pi.config").opts.export_open then
    if vim.ui.open then
      pcall(vim.ui.open, path)
    else
      pcall(vim.cmd, "edit " .. vim.fn.fnameescape(path))
    end
  end
  return path
end

function M.stop_job()
  require("pi.client").stop()
end

return M
