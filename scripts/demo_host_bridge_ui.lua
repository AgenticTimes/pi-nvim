-- Interactive visual demo: watch pi→nvim host edit in a float.
-- Run inside a real Neovim UI (not -l only):
--   :luafile ~/source/pi.nvim/scripts/demo_host_bridge_ui.lua
-- or:
--   nvim -u NONE -c "luafile ~/source/pi.nvim/scripts/demo_host_bridge_ui.lua"

local root = vim.fn.fnamemodify(
  (debug.getinfo(1, "S").source:sub(2)),
  ":p:h:h"
)
local ext = root .. "/extensions/host_nvim_demo.ts"
local HOST_TITLE = "__nvim_host__"

local scratch = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(scratch, "pi://host-demo")
vim.bo[scratch].bufhidden = "wipe"
vim.bo[scratch].modifiable = true
vim.api.nvim_buf_set_lines(scratch, 0, -1, false, {
  "-- Watching pi → Neovim host bridge --",
  "-- waiting for /nvim_host_demo … --",
  "",
})

local width = math.floor(vim.o.columns * 0.7)
local height = math.floor(vim.o.lines * 0.5)
local win = vim.api.nvim_open_win(scratch, true, {
  relative = "editor",
  width = width,
  height = height,
  row = math.floor((vim.o.lines - height) / 2),
  col = math.floor((vim.o.columns - width) / 2),
  style = "minimal",
  border = "rounded",
  title = " pi.nvim host demo ",
  title_pos = "center",
})
vim.wo[win].cursorline = true

local function status(msg)
  local lines = vim.api.nvim_buf_get_lines(scratch, 0, -1, false)
  -- keep header, replace status line (index 2 / line 3)
  while #lines < 3 do
    table.insert(lines, "")
  end
  lines[2] = "-- " .. msg .. " --"
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
  vim.cmd("redraw")
end

local job
local acc = ""

local function send(obj)
  vim.fn.chansend(job, vim.json.encode(obj) .. "\n")
end

local function apply_host_op(placeholder)
  local ok, op = pcall(vim.json.decode, placeholder or "")
  if not ok or type(op) ~= "table" then
    return false, "bad op"
  end
  if op.op == "append_line" then
    status("applying append_line via nvim_buf_set_lines …")
    vim.cmd("redraw")
    vim.wait(400) -- brief pause so you can see the moment
    local lines = vim.api.nvim_buf_get_lines(scratch, 0, -1, false)
    table.insert(lines, "")
    table.insert(lines, ">>> " .. tostring(op.text or ""))
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
    -- jump cursor to new line
    local last = vim.api.nvim_buf_line_count(scratch)
    vim.api.nvim_win_set_cursor(win, { last, 0 })
    vim.cmd("redraw")
    return true, "appended:" .. tostring(last)
  end
  return false, "unknown op"
end

local function on_msg(obj)
  if obj.type == "extension_ui_request" and obj.method == "input" and obj.title == HOST_TITLE then
    status("got extension_ui_request from pi")
    local ok, result = apply_host_op(obj.placeholder)
    send({
      type = "extension_ui_response",
      id = obj.id,
      value = ok and result or ("error:" .. tostring(result)),
    })
    status(ok and ("PASS — " .. tostring(result)) or ("FAIL — " .. tostring(result)))
    vim.notify("pi.nvim demo: " .. (ok and "PASS" or "FAIL"), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
    return
  end
  if obj.type == "extension_ui_request" and obj.method == "notify" then
    status("pi notify: " .. tostring(obj.message or ""))
  end
  if obj.type == "response" and obj.command == "prompt" and obj.success == false then
    status("prompt failed: " .. tostring(obj.error))
    vim.notify("pi prompt failed: " .. tostring(obj.error), vim.log.levels.ERROR)
  end
end

local function on_stdout(_, data)
  for _, chunk in ipairs(data or {}) do
    if chunk ~= "" then
      acc = acc .. chunk .. "\n"
      while true do
        local nl = acc:find("\n", 1, true)
        if not nl then
          break
        end
        local line = acc:sub(1, nl - 1):gsub("\r$", "")
        acc = acc:sub(nl + 1)
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

status("starting pi --mode rpc …")
job = vim.fn.jobstart({
  "pi",
  "--mode",
  "rpc",
  "--no-session",
  "--no-extensions",
  "-e",
  ext,
}, {
  on_stdout = on_stdout,
  on_stderr = function(_, data)
    for _, l in ipairs(data or {}) do
      if l ~= "" then
        status("pi stderr: " .. l)
      end
    end
  end,
  on_exit = function(_, code)
    status("pi exited: " .. tostring(code) .. "  (q closes float)")
  end,
})

if job <= 0 then
  status("FAIL: could not start pi")
  return
end

vim.defer_fn(function()
  status("sending /nvim_host_demo …")
  send({ id = "ui-demo-1", type = "prompt", message = "/nvim_host_demo" })
end, 800)

vim.keymap.set("n", "q", function()
  if job > 0 then
    pcall(vim.fn.jobstop, job)
  end
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end, { buffer = scratch, nowait = true, desc = "close host demo" })

vim.notify("pi.nvim visual demo running — watch the float; press q to close", vim.log.levels.INFO)
