-- Real edit demo: open demo/sample.lua, pi asks Neovim to change greet() in-buffer.
--
--   nvim ~/source/pi.nvim/demo/sample.lua \
--     -c "luafile ~/source/pi.nvim/scripts/demo_real_edit_ui.lua"
--
-- Or from repo root inside nvim:
--   :e demo/sample.lua | :luafile scripts/demo_real_edit_ui.lua
--
-- Watch the return line change. q closes the helper split (keeps the file).

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local ext = root .. "/extensions/host_edit_demo.ts"
local sample = root .. "/demo/sample.lua"
local HOST_TITLE = "__nvim_host__"

local job ---@type integer|nil
local acc = ""

local function send(obj)
  vim.fn.chansend(job, vim.json.encode(obj) .. "\n")
end

-- Ensure sample is the current buffer and visible
vim.cmd("edit " .. vim.fn.fnameescape(sample))
local buf = vim.api.nvim_get_current_buf()
vim.cmd("setlocal cursorline")

-- Small status split below so file stays front-and-center
vim.cmd("botright 6split")
local status_win = vim.api.nvim_get_current_win()
local status_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(status_win, status_buf)
vim.bo[status_buf].bufhidden = "wipe"
vim.keymap.set("n", "q", function()
  if job and job > 0 then
    pcall(vim.fn.jobstop, job)
  end
  if vim.api.nvim_win_is_valid(status_win) then
    vim.api.nvim_win_close(status_win, true)
  end
end, { buffer = status_buf, nowait = true })

-- focus back on code
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_buf(w) == buf then
    vim.api.nvim_set_current_win(w)
    break
  end
end

local function set_status(lines)
  vim.api.nvim_buf_set_lines(status_buf, 0, -1, false, lines)
  vim.cmd("redraw")
end

set_status({
  "pi.nvim REAL edit demo",
  "1) look at greet() above",
  "2) wait — pi will change the return line via Neovim API",
  "starting pi …",
})

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

local function apply_replace(op)
  local path = op.path
  if not path:match("^/") then
    path = root .. "/" .. path
  end
  local b = buffer_for(path)
  if not b then
    -- open if needed
    vim.cmd("badd " .. vim.fn.fnameescape(path))
    b = buffer_for(path)
  end
  if not b then
    return false, "buffer not found: " .. path
  end

  local old = op.old_text
  local new = op.new_text
  if type(old) ~= "string" or type(new) ~= "string" then
    return false, "missing old_text/new_text"
  end

  local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
  local text = table.concat(lines, "\n")
  local idx = text:find(old, 1, true)
  if not idx then
    return false, "old_text not found in buffer"
  end

  set_status({
    "pi.nvim REAL edit demo",
    "applying replace_in_buffer via nvim_buf_set_lines …",
    "old: " .. old,
    "new: " .. new,
  })
  vim.wait(500)

  local replaced = text:sub(1, idx - 1) .. new .. text:sub(idx + #old)
  local new_lines = vim.split(replaced, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, new_lines)

  -- jump to changed line
  local changed_row = 1
  for i, line in ipairs(new_lines) do
    if line:find("hi from pi", 1, true) then
      changed_row = i
      break
    end
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == b then
      vim.api.nvim_set_current_win(w)
      vim.api.nvim_win_set_cursor(w, { changed_row, 0 })
      break
    end
  end
  vim.cmd("redraw")
  return true, "replaced in " .. vim.fn.fnamemodify(path, ":.")
end

local function on_msg(obj)
  if obj.type == "extension_ui_request" and obj.method == "input" and obj.title == HOST_TITLE then
    local okj, op = pcall(vim.json.decode, obj.placeholder or "")
    if not okj or type(op) ~= "table" then
      send({ type = "extension_ui_response", id = obj.id, value = "error:bad json" })
      return
    end
    local ok, result = false, "unknown"
    if op.op == "replace_in_buffer" then
      ok, result = apply_replace(op)
    else
      result = "unknown op " .. tostring(op.op)
    end
    send({
      type = "extension_ui_response",
      id = obj.id,
      value = ok and result or ("error:" .. tostring(result)),
    })
    set_status({
      ok and "PASS — code above was edited by Neovim API (buffer may be modified, not saved)"
        or ("FAIL — " .. tostring(result)),
      "Look at greet() in the file window.",
      "q in this status split to stop pi / close status",
    })
    vim.notify(ok and "REAL edit applied in buffer" or tostring(result), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
    return
  end
  if obj.type == "response" and obj.command == "prompt" and obj.success == false then
    set_status({ "prompt failed: " .. tostring(obj.error) })
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

job = vim.fn.jobstart({
  "pi",
  "--mode",
  "rpc",
  "--no-session",
  "--no-extensions",
  "-e",
  ext,
}, {
  cwd = root,
  on_stdout = on_stdout,
  on_stderr = function(_, data)
    for _, l in ipairs(data or {}) do
      if l ~= "" then
        set_status({ "pi stderr: " .. l })
      end
    end
  end,
})

if job <= 0 then
  set_status({ "FAIL: could not start pi" })
  return
end

vim.defer_fn(function()
  set_status({
    "pi.nvim REAL edit demo",
    "sending /nvim_edit_sample …",
    "watch the return line in sample.lua",
  })
  send({ id = "real-1", type = "prompt", message = "/nvim_edit_sample" })
end, 800)
