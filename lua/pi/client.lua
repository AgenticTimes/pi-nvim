-- JSONL RPC client for pi --mode rpc
local M = {}

local job_id ---@type integer|nil
local acc = ""
local pending = {} ---@type table<string, {resolve:fun(any), timer:any}>
local on_event_cb ---@type fun(ev:table)|nil
local seq = 0

local function handle_line(line)
  line = line:gsub("\r$", "")
  if line == "" then
    return
  end
  local ok, obj = pcall(vim.json.decode, line)
  if not ok or type(obj) ~= "table" then
    return
  end
  if obj.type == "response" and obj.id and pending[obj.id] then
    local p = pending[obj.id]
    pending[obj.id] = nil
    if p.timer then
      pcall(vim.fn.timer_stop, p.timer)
    end
    p.resolve(obj)
    return
  end
  if on_event_cb then
    on_event_cb(obj)
  end
end

--- Feed raw stdout bytes. Do NOT invent newlines — large JSONL lines arrive
--- as partial chunks across on_stdout calls; a false NL corrupts decode.
function M._feed_for_test(chunk)
  acc = acc .. (chunk or "")
  while true do
    local nl = acc:find("\n", 1, true)
    if not nl then
      break
    end
    local line = acc:sub(1, nl - 1)
    acc = acc:sub(nl + 1)
    handle_line(line)
  end
end

function M.is_running()
  return job_id ~= nil and job_id > 0
end

function M.start(opts)
  opts = opts or {}
  if M.is_running() then
    return job_id
  end
  acc = ""
  on_event_cb = opts.on_event
  local cmd = opts.cmd or { "pi", "--mode", "rpc" }
  job_id = vim.fn.jobstart(cmd, {
    cwd = opts.cwd,
    stdout_buffered = false,
    on_stdout = function(_, data)
      -- Neovim splits on NL: items[1..n-1] are complete lines; last may be
      -- partial. Empty last string means the previous item already ended with NL.
      if type(data) ~= "table" then
        return
      end
      local n = #data
      for i = 1, n do
        local chunk = data[i]
        if i < n then
          M._feed_for_test(chunk .. "\n")
        elseif chunk ~= "" then
          M._feed_for_test(chunk)
        end
      end
    end,
    on_stderr = function(_, data)
      if opts.on_stderr then
        opts.on_stderr(data)
      end
    end,
    on_exit = function(_, code)
      job_id = nil
      if opts.on_exit then
        opts.on_exit(code)
      end
    end,
  })
  if not job_id or job_id <= 0 then
    job_id = nil
    error("pi.client: failed to start job")
  end
  return job_id
end

function M.send(obj)
  if not M.is_running() then
    error("pi.client: not running")
  end
  vim.fn.chansend(job_id, vim.json.encode(obj) .. "\n")
end

function M.request(obj, timeout_ms)
  timeout_ms = timeout_ms or 30000
  seq = seq + 1
  local id = obj.id or ("req-" .. tostring(seq))
  obj.id = id
  local co = coroutine.running()
  if not co then
    local result
    pending[id] = {
      resolve = function(r)
        result = r
      end,
    }
    M.send(obj)
    vim.wait(timeout_ms, function()
      return result ~= nil
    end, 20)
    pending[id] = nil
    if not result then
      return nil, "timeout"
    end
    return result
  end
end

function M.set_on_event(cb)
  on_event_cb = cb
end

function M.stop()
  if job_id and job_id > 0 then
    pcall(vim.fn.jobstop, job_id)
  end
  job_id = nil
  acc = ""
  pending = {}
end

return M
