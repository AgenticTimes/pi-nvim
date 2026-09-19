-- pi LLM toolcall → Neovim buffer edit (visible).
--
--   nvim ~/source/pi.nvim/demo/sample.lua \
--     -c "luafile ~/source/pi.nvim/scripts/demo_toolcall_ui.lua"
--
-- Top: sample.lua (watch greet() change)
-- Bottom: live log of pi events (must see tool_execution_start for nvim_replace_in_buffer)
-- q in log window: stop

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local ext = root .. "/extensions/nvim_replace_tool.ts"
local sample = root .. "/demo/sample.lua"
local HOST_TITLE = "__nvim_host__"

-- restore pristine sample on disk for a clean before/after
vim.fn.writefile({
  "-- Sample file for the visual host-edit demo.",
  "-- The agent bridge will change greet() below in this buffer.",
  "",
  "local M = {}",
  "",
  "function M.greet(name)",
  '  return "hello, " .. tostring(name)',
  "end",
  "",
  "return M",
}, sample)

vim.cmd("edit! " .. vim.fn.fnameescape(sample))
local code_buf = vim.api.nvim_get_current_buf()

vim.cmd("botright 12split")
local log_win = vim.api.nvim_get_current_win()
local log_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(log_win, log_buf)
vim.bo[log_buf].bufhidden = "wipe"
vim.bo[log_buf].modifiable = true

local job ---@type integer|nil
local acc = ""
local log_lines = {
  "=== pi toolcall → Neovim (live) ===",
  "Waiting for pi to call tool: nvim_replace_in_buffer",
  "",
}

local function redraw_log()
  vim.api.nvim_buf_set_lines(log_buf, 0, -1, false, log_lines)
  if vim.api.nvim_win_is_valid(log_win) then
    pcall(vim.api.nvim_win_set_cursor, log_win, { #log_lines, 0 })
  end
  vim.cmd("redraw")
end

local function log(msg)
  table.insert(log_lines, os.date("%H:%M:%S ") .. msg)
  redraw_log()
end

-- focus code
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_buf(w) == code_buf then
    vim.api.nvim_set_current_win(w)
    break
  end
end

vim.keymap.set("n", "q", function()
  pcall(vim.cmd, "diffoff!")
  if job and job > 0 then
    pcall(vim.fn.jobstop, job)
  end
  if vim.api.nvim_win_is_valid(log_win) then
    vim.api.nvim_win_close(log_win, true)
  end
end, { buffer = log_buf, nowait = true })

local function send(obj)
  vim.fn.chansend(job, vim.json.encode(obj) .. "\n")
end

local function norm(p)
  return vim.fn.fnamemodify(p, ":p")
end

local function buffer_for(path)
  local abs = norm(path)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= "" and norm(name) == abs then
        return b
      end
    end
  end
  return nil
end

local function open_diff(before_lines, after_buf, changed_row)
  local before_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(before_buf, "pi://before")
  vim.api.nvim_buf_set_lines(before_buf, 0, -1, false, before_lines)
  vim.bo[before_buf].buftype = "nofile"
  vim.bo[before_buf].bufhidden = "wipe"
  vim.bo[before_buf].modifiable = false
  vim.bo[before_buf].filetype = vim.bo[after_buf].filetype

  local after_win
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == after_buf then
      after_win = w
      break
    end
  end
  if not after_win then
    log("diff: no window for after buffer")
    return
  end

  vim.api.nvim_set_current_win(after_win)
  vim.cmd("leftabove vsplit")
  local before_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(before_win, before_buf)
  pcall(vim.api.nvim_set_option_value, "winbar", " BEFORE (original) ", { win = before_win })
  pcall(vim.api.nvim_set_option_value, "winbar", " AFTER (pi tool → nvim) ", { win = after_win })

  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(after_win)
  vim.cmd("diffthis")

  local row = changed_row or 1
  pcall(vim.api.nvim_win_set_cursor, before_win, { row, 0 })
  pcall(vim.api.nvim_win_set_cursor, after_win, { row, 0 })
  vim.cmd("redraw")
  log("diff-mode ON: left=BEFORE right=AFTER (highlights = changes)")
end

local function apply_replace(op)
  local path = op.path
  if type(path) ~= "string" then
    return false, "no path"
  end
  if not path:match("^/") then
    path = root .. "/" .. path
  end
  local b = buffer_for(path) or code_buf
  local old, new = op.old_text, op.new_text
  if type(old) ~= "string" or type(new) ~= "string" then
    return false, "missing old/new"
  end
  local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
  local text = table.concat(lines, "\n")
  -- models often drop indent; try exact then loose leading-space match
  local idx = text:find(old, 1, true)
  if not idx then
    local loose_old = old:gsub("^%s+", "")
    local loose_idx = text:find(loose_old, 1, true)
    if loose_idx then
      -- expand match to full line indent in buffer
      local line_start = text:sub(1, loose_idx):match(".*\n()") or 1
      local line_end = text:find("\n", loose_idx, true) or (#text + 1)
      local line = text:sub(line_start, line_end - 1)
      if line:find(loose_old, 1, true) then
        old = line
        idx = line_start
        -- keep new_text indent aligned with matched line
        local indent = line:match("^(%s*)") or ""
        new = indent .. new:gsub("^%s+", "")
      end
    end
  end
  if not idx then
    return false, "old_text not found"
  end

  local before_lines = vim.deepcopy(lines)
  log("Neovim APPLY: nvim_buf_set_lines on " .. vim.fn.fnamemodify(path, ":."))
  vim.wait(200)
  local replaced = text:sub(1, idx - 1) .. new .. text:sub(idx + #old)
  local new_lines = vim.split(replaced, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, new_lines)

  local changed_row = 1
  for i, line in ipairs(new_lines) do
    if before_lines[i] ~= line then
      changed_row = i
      break
    end
  end

  open_diff(before_lines, b, changed_row)
  return true, "buffer edited + diff-mode"
end

local saw_tool = false
local saw_apply = false

local function on_msg(obj)
  local t = obj.type
  if t == "tool_execution_start" then
    saw_tool = true
    log("pi TOOLCALL start: " .. tostring(obj.toolName) .. " id=" .. tostring(obj.toolCallId))
    if obj.args or obj.input or obj.toolArguments then
      local a = obj.args or obj.input or obj.toolArguments
      log("  args: " .. vim.inspect(a):gsub("%s+", " "):sub(1, 200))
    end
    return
  end
  if t == "tool_execution_end" then
    log("pi TOOLCALL end: " .. tostring(obj.toolName) .. " isError=" .. tostring(obj.isError))
    return
  end
  if t == "agent_start" then
    log("pi agent_start")
    return
  end
  if t == "agent_end" then
    log("pi agent_end")
    if saw_tool and saw_apply then
      log("PASS: pi called tool AND Neovim showed the edit")
      vim.notify("PASS: real pi toolcall → visible Neovim edit", vim.log.levels.INFO)
    elseif not saw_tool then
      log("FAIL: never saw tool_execution_start (model did not call the tool?)")
    elseif not saw_apply then
      log("FAIL: tool ran but host edit did not apply")
    end
    return
  end
  if t == "message_update" and obj.assistantMessageEvent and obj.assistantMessageEvent.type == "text_delta" then
    -- keep log quiet; optional tiny hint
    return
  end
  if t == "extension_ui_request" and obj.method == "input" and obj.title == HOST_TITLE then
    log("pi → host request (extension_ui_request)")
    local okj, op = pcall(vim.json.decode, obj.placeholder or "")
    if not okj then
      send({ type = "extension_ui_response", id = obj.id, value = "error:bad json" })
      return
    end
    local ok, result = apply_replace(op)
    saw_apply = ok
    send({
      type = "extension_ui_response",
      id = obj.id,
      value = ok and result or ("error:" .. tostring(result)),
    })
    log(ok and ("host DONE: " .. tostring(result)) or ("host FAIL: " .. tostring(result)))
    return
  end
  if t == "extension_ui_request" and obj.method == "notify" then
    log("pi notify: " .. tostring(obj.message))
    return
  end
  if t == "response" and obj.command == "prompt" then
    log("prompt accepted=" .. tostring(obj.success) .. (obj.error and (" err=" .. obj.error) or ""))
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

log("starting: pi --mode rpc --no-builtin-tools -t nvim_replace_in_buffer")
job = vim.fn.jobstart({
  "pi",
  "--mode",
  "rpc",
  "--no-session",
  "--no-extensions",
  "--no-builtin-tools",
  "-t",
  "nvim_replace_in_buffer",
  "-e",
  ext,
}, {
  cwd = root,
  on_stdout = on_stdout,
  on_stderr = function(_, data)
    for _, l in ipairs(data or {}) do
      if l ~= "" then
        log("stderr: " .. l)
      end
    end
  end,
  on_exit = function(_, code)
    log("pi exited: " .. tostring(code))
  end,
})

if not job or job <= 0 then
  log("FAIL: could not start pi")
  return
end

local prompt = table.concat({
  "You are required to call the tool nvim_replace_in_buffer exactly once.",
  "Do not write files yourself. Do not use any other tool.",
  "Arguments MUST be exactly:",
  'path: "demo/sample.lua"',
  'old_text: "  return \\"hello, \\" .. tostring(name)"',
  'new_text: "  return \\"hi from pi→nvim, \\" .. tostring(name)"',
  "After the tool returns, reply with one word: DONE",
}, "\n")

vim.defer_fn(function()
  log("Neovim → pi: prompt (ask model to toolcall)")
  send({ id = "tc-1", type = "prompt", message = prompt })
end, 1000)

vim.notify("Watch TOP=code, BOTTOM=pi tool events. q in log to stop.", vim.log.levels.INFO)
redraw_log()
