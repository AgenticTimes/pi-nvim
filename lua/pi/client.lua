-- JSONL RPC client for pi --mode rpc (multi-instance capable)
local M = {}

---@class PiClient
---@field job_id integer|nil
---@field acc string
---@field pending table
---@field on_event_cb fun(ev:table)|nil
---@field seq integer

local function make_client()
  ---@type PiClient
  local C = {
    job_id = nil,
    acc = "",
    pending = {},
    on_event_cb = nil,
    seq = 0,
  }

  local function handle_line(line)
    line = line:gsub("\r$", "")
    if line == "" then
      return
    end
    if #line > 262144 then
      return
    end
    local ok, obj = pcall(vim.json.decode, line)
    if not ok or type(obj) ~= "table" then
      return
    end
    if obj.type == "response" and obj.id and C.pending[obj.id] then
      local p = C.pending[obj.id]
      C.pending[obj.id] = nil
      if p.timer then
        pcall(vim.fn.timer_stop, p.timer)
      end
      p.resolve(obj)
      return
    end
    if C.on_event_cb then
      C.on_event_cb(obj)
    end
  end

  --- Feed raw stdout bytes. Do NOT invent newlines — large JSONL lines arrive
  --- as partial chunks across on_stdout calls; a false NL corrupts decode.
  function C._feed_for_test(chunk)
    C.acc = C.acc .. (chunk or "")
    while true do
      local nl = C.acc:find("\n", 1, true)
      if not nl then
        break
      end
      local line = C.acc:sub(1, nl - 1)
      C.acc = C.acc:sub(nl + 1)
      handle_line(line)
    end
  end

  function C.is_running()
    return C.job_id ~= nil and C.job_id > 0
  end

  function C.start(opts)
    opts = opts or {}
    if C.is_running() then
      return C.job_id
    end
    C.acc = ""
    C.on_event_cb = opts.on_event
    local cmd = opts.cmd or { "pi", "--mode", "rpc" }
    C.job_id = vim.fn.jobstart(cmd, {
      cwd = opts.cwd,
      stdout_buffered = false,
      on_stdout = function(_, data)
        if type(data) ~= "table" then
          return
        end
        local n = #data
        for i = 1, n do
          local chunk = data[i]
          if i < n then
            C._feed_for_test(chunk .. "\n")
          elseif chunk ~= "" then
            C._feed_for_test(chunk)
          end
        end
      end,
      on_stderr = function(_, data)
        if opts.on_stderr then
          opts.on_stderr(data)
        end
      end,
      on_exit = function(_, code)
        C.job_id = nil
        if opts.on_exit then
          opts.on_exit(code)
        end
      end,
    })
    if not C.job_id or C.job_id <= 0 then
      C.job_id = nil
      error("pi.client: failed to start job")
    end
    return C.job_id
  end

  function C.send(obj)
    if not C.is_running() then
      error("pi.client: not running")
    end
    vim.fn.chansend(C.job_id, vim.json.encode(obj) .. "\n")
  end

  function C.request(obj, timeout_ms)
    timeout_ms = timeout_ms or 30000
    C.seq = C.seq + 1
    local id = obj.id or ("req-" .. tostring(C.seq))
    obj.id = id
    local co = coroutine.running()
    if not co then
      local result
      C.pending[id] = {
        resolve = function(r)
          result = r
        end,
      }
      C.send(obj)
      vim.wait(timeout_ms, function()
        return result ~= nil
      end, 20)
      C.pending[id] = nil
      if not result then
        return nil, "timeout"
      end
      return result
    end
  end

  function C.set_on_event(cb)
    C.on_event_cb = cb
  end

  function C.stop()
    if C.job_id and C.job_id > 0 then
      pcall(vim.fn.jobstop, C.job_id)
    end
    C.job_id = nil
    C.acc = ""
    C.pending = {}
  end

  return C
end

local default = make_client()

--- Create an isolated RPC client (one pi job).
function M.new()
  return make_client()
end

function M.default()
  return default
end

-- Singleton facade (backward compatible)
function M._feed_for_test(chunk)
  return default._feed_for_test(chunk)
end
function M.is_running()
  return default.is_running()
end
function M.start(opts)
  return default.start(opts)
end
function M.send(obj)
  return default.send(obj)
end
function M.request(obj, timeout_ms)
  return default.request(obj, timeout_ms)
end
function M.set_on_event(cb)
  return default.set_on_event(cb)
end
function M.stop()
  return default.stop()
end

return M
