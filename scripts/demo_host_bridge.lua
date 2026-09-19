-- Feasibility spike: Neovim hosts pi --mode rpc and executes host tool ops.
-- Run:
--   cd ~/source/pi.nvim && nvim -u NONE -l scripts/demo_host_bridge.lua
--
-- Exit 0 = PASS (scratch buffer got a line from pi via extension_ui bridge)

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local ext = root .. "/extensions/host_nvim_demo.ts"
local HOST_TITLE = "__nvim_host__"

local scratch = vim.api.nvim_create_buf(true, true)
vim.api.nvim_buf_set_name(scratch, "pi://host-demo")
vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "-- host demo buffer --" })

local job
local buf = ""
local done = false
local pass = false
local err_msg = nil
local got_ui_request = false

local function send(obj)
  vim.fn.chansend(job, vim.json.encode(obj) .. "\n")
end

local function apply_host_op(placeholder)
  local ok, op = pcall(vim.json.decode, placeholder or "")
  if not ok or type(op) ~= "table" then
    return false, "bad op json: " .. tostring(placeholder)
  end
  if op.op == "append_line" then
    local lines = vim.api.nvim_buf_get_lines(scratch, 0, -1, false)
    table.insert(lines, tostring(op.text or ""))
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
    return true, "appended:" .. tostring(#lines)
  end
  return false, "unknown op"
end

local function on_msg(obj)
  if obj.type == "extension_ui_request" and obj.method == "input" and obj.title == HOST_TITLE then
    got_ui_request = true
    local ok, result = apply_host_op(obj.placeholder)
    send({
      type = "extension_ui_response",
      id = obj.id,
      value = ok and result or ("error:" .. tostring(result)),
    })
    return
  end

  if obj.type == "extension_ui_request" and obj.method == "notify" then
    -- fire-and-forget
    if type(obj.message) == "string" and obj.message:find("nvim host result", 1, true) then
      local lines = vim.api.nvim_buf_get_lines(scratch, 0, -1, false)
      if got_ui_request and #lines >= 2 then
        pass = true
        done = true
      end
    end
    return
  end

  if obj.type == "response" and obj.command == "prompt" and obj.success == false then
    err_msg = obj.error or "prompt failed"
    done = true
  end
end

local function on_stdout(_, data, _)
  if not data then
    return
  end
  for _, chunk in ipairs(data) do
    if chunk ~= "" then
      buf = buf .. chunk .. "\n"
      while true do
        local nl = buf:find("\n", 1, true)
        if not nl then
          break
        end
        local line = buf:sub(1, nl - 1)
        buf = buf:sub(nl + 1)
        line = line:gsub("\r$", "")
        if line ~= "" then
          local ok, obj = pcall(vim.json.decode, line)
          if ok and type(obj) == "table" then
            on_msg(obj)
          end
        end
      end
    end
  end
end

local stderr_acc = {}

job = vim.fn.jobstart({
  "pi",
  "--mode",
  "rpc",
  "--no-session",
  "--no-extensions",
  "-e",
  ext,
}, {
  stdout_buffered = false,
  stderr_buffered = false,
  on_stdout = on_stdout,
  on_stderr = function(_, data)
    for _, l in ipairs(data or {}) do
      if l ~= "" then
        table.insert(stderr_acc, l)
      end
    end
  end,
  on_exit = function(_, code)
    if not done then
      err_msg = "pi exited early: " .. tostring(code)
      done = true
    end
  end,
})

if job <= 0 then
  io.stderr:write("FAIL: could not start pi\n")
  os.exit(1)
end

-- Give pi a moment to boot, then invoke extension command (no LLM).
vim.defer_fn(function()
  send({ id = "demo-1", type = "prompt", message = "/nvim_host_demo" })
end, 800)

-- Timeout watchdog
vim.defer_fn(function()
  if not done then
    err_msg = "timeout waiting for host bridge"
    done = true
  end
end, 15000)

vim.wait(16000, function()
  return done
end, 50)

pcall(vim.fn.jobstop, job)

local lines = vim.api.nvim_buf_get_lines(scratch, 0, -1, false)
if pass then
  io.write("PASS: host tool bridge works\n")
  io.write("scratch buffer:\n")
  for _, l in ipairs(lines) do
    io.write("  " .. l .. "\n")
  end
  os.exit(0)
end

io.stderr:write("FAIL: " .. tostring(err_msg or "unknown") .. "\n")
io.stderr:write("got_ui_request=" .. tostring(got_ui_request) .. "\n")
io.stderr:write("scratch:\n")
for _, l in ipairs(lines) do
  io.stderr:write("  " .. l .. "\n")
end
if #stderr_acc > 0 then
  io.stderr:write("pi stderr (tail):\n")
  for i = math.max(1, #stderr_acc - 40), #stderr_acc do
    io.stderr:write("  " .. stderr_acc[i] .. "\n")
  end
end
os.exit(1)
