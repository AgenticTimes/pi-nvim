-- Multi-file demo + accept/reject review
--
--   cd ~/source/pi.nvim && nvim -c "luafile scripts/demo_multifile_ui.lua"
--
-- Layout:
--   left:   touched file list
--   mid:    BEFORE | AFTER diff
--   bottom: pi tool events
--
-- Keys (list / log / diff buffers):
--   a     accept current file → keep AFTER, remove from list, show next
--   r     reject current file → restore BEFORE, remove from list
--   ]f [f next / prev file
--   <CR>  open file under cursor (list)
--   q     stop pi / close panels

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local ext = root .. "/extensions/nvim_replace_tool.ts"
local HOST_TITLE = "__nvim_host__"

vim.opt.swapfile = false
vim.opt.shortmess:append("A")
vim.opt.hidden = true

local seeds = {
  {
    rel = "demo/mod_a.lua",
    lines = {
      "-- Multi-file demo samples",
      "local M = {}",
      "function M.version()",
      '  return "v1"',
      "end",
      "return M",
    },
  },
  {
    rel = "demo/mod_b.lua",
    lines = {
      "local M = {}",
      "function M.name()",
      '  return "alpha"',
      "end",
      "return M",
    },
  },
  {
    rel = "demo/mod_c.lua",
    lines = {
      "local M = {}",
      "function M.enabled()",
      "  return false",
      "end",
      "return M",
    },
  },
}

for _, f in ipairs(seeds) do
  vim.fn.writefile(f.lines, root .. "/" .. f.rel)
end

---@type { path:string, rel:string, before:string[], buf:integer, changed_row:integer }[]
local touched = {}
local file_idx = 0

local list_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(list_buf, "pi://touched")
vim.bo[list_buf].bufhidden = "wipe"

local log_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(log_buf, "pi://log")
vim.bo[log_buf].bufhidden = "wipe"

vim.cmd("edit! " .. vim.fn.fnameescape(root .. "/" .. seeds[1].rel))
local code_win = vim.api.nvim_get_current_win()

vim.cmd("topleft 30vsplit")
local list_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(list_win, list_buf)
pcall(vim.api.nvim_set_option_value, "winbar", " pending files ", { win = list_win })

vim.api.nvim_set_current_win(code_win)
vim.cmd("botright 10split")
local log_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(log_win, log_buf)
pcall(vim.api.nvim_set_option_value, "winbar", " pi tool events ", { win = log_win })
vim.api.nvim_set_current_win(code_win)

local job ---@type integer|nil
local acc = ""
local log_lines = { "=== multi-file + accept/reject ===", "a=accept  r=reject  ]f/[f", "" }
local before_win ---@type integer|nil

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

local function redraw_list()
  local lines = {
    "pending (" .. #touched .. ")",
    "a accept · r reject",
    "]f/[f · <CR> open",
    "",
  }
  for i, t in ipairs(touched) do
    local mark = (i == file_idx) and ">" or " "
    table.insert(lines, string.format("%s %d. %s", mark, i, t.rel))
  end
  if #touched == 0 then
    table.insert(lines, "(empty)")
  end
  vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
  vim.cmd("redraw")
end

local function close_diff_wins()
  pcall(vim.cmd, "diffoff!")
  if before_win and vim.api.nvim_win_is_valid(before_win) then
    pcall(vim.api.nvim_win_close, before_win, true)
  end
  before_win = nil
end

local map_review_keys -- forward decl
local show_file
local show_empty_review

show_empty_review = function()
  close_diff_wins()
  file_idx = 0
  if vim.api.nvim_win_is_valid(code_win) then
    local empty = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(empty, 0, -1, false, {
      "No pending diffs.",
      "Accepted files stay as edited; rejected were restored.",
    })
    vim.api.nvim_win_set_buf(code_win, empty)
    pcall(vim.api.nvim_set_option_value, "winbar", " review clear ", { win = code_win })
  end
  redraw_list()
end

show_file = function(idx)
  if idx < 1 or idx > #touched then
    show_empty_review()
    return
  end
  file_idx = idx
  local t = touched[idx]
  close_diff_wins()
  if not vim.api.nvim_win_is_valid(code_win) then
    return
  end

  vim.api.nvim_set_current_win(code_win)
  vim.api.nvim_win_set_buf(code_win, t.buf)
  pcall(
    vim.api.nvim_set_option_value,
    "winbar",
    " AFTER " .. t.rel .. "  [a]ccept [r]eject ",
    { win = code_win }
  )

  local bname = "pi://before/" .. t.rel
  local before_buf = vim.fn.bufnr(bname)
  if before_buf > 0 and vim.api.nvim_buf_is_valid(before_buf) then
    vim.bo[before_buf].modifiable = true
    vim.api.nvim_buf_set_lines(before_buf, 0, -1, false, t.before)
  else
    before_buf = vim.api.nvim_create_buf(false, true)
    pcall(vim.api.nvim_buf_set_name, before_buf, bname)
    vim.api.nvim_buf_set_lines(before_buf, 0, -1, false, t.before)
  end
  vim.bo[before_buf].buftype = "nofile"
  vim.bo[before_buf].bufhidden = "hide"
  vim.bo[before_buf].modifiable = false
  vim.bo[before_buf].filetype = vim.bo[t.buf].filetype

  vim.cmd("leftabove vsplit")
  before_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(before_win, before_buf)
  pcall(vim.api.nvim_set_option_value, "winbar", " BEFORE ", { win = before_win })

  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(code_win)
  vim.cmd("diffthis")

  local row = t.changed_row or 1
  pcall(vim.api.nvim_win_set_cursor, before_win, { row, 0 })
  pcall(vim.api.nvim_win_set_cursor, code_win, { row, 0 })

  map_review_keys(t.buf)
  map_review_keys(before_buf)
  redraw_list()
  log(string.format("viewing %d/%d %s", idx, #touched, t.rel))
  vim.cmd("redraw")
end

local function accept_current()
  if file_idx < 1 or file_idx > #touched then
    log("accept: nothing pending")
    return
  end
  local t = touched[file_idx]
  local rel = t.rel
  pcall(vim.api.nvim_buf_call, t.buf, function()
    vim.cmd("silent! write")
  end)
  table.remove(touched, file_idx)
  log("ACCEPTED & removed from list: " .. rel .. " (" .. #touched .. " left)")
  vim.notify("Accepted " .. rel, vim.log.levels.INFO)
  if #touched == 0 then
    show_empty_review()
  else
    show_file(math.min(file_idx, #touched))
  end
end

local function reject_current()
  if file_idx < 1 or file_idx > #touched then
    log("reject: nothing pending")
    return
  end
  local t = touched[file_idx]
  local rel = t.rel
  vim.api.nvim_buf_set_lines(t.buf, 0, -1, false, t.before)
  vim.bo[t.buf].modified = false
  table.remove(touched, file_idx)
  log("REJECTED (restored) & removed: " .. rel .. " (" .. #touched .. " left)")
  vim.notify("Rejected " .. rel, vim.log.levels.WARN)
  if #touched == 0 then
    show_empty_review()
  else
    show_file(math.min(file_idx, #touched))
  end
end

local function next_file(delta)
  if #touched == 0 then
    return
  end
  local i = file_idx + delta
  if i < 1 then
    i = #touched
  elseif i > #touched then
    i = 1
  end
  show_file(i)
end

map_review_keys = function(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local opts = { buffer = bufnr, nowait = true, silent = true }
  vim.keymap.set("n", "a", accept_current, opts)
  vim.keymap.set("n", "r", reject_current, opts)
  vim.keymap.set("n", "]f", function()
    next_file(1)
  end, opts)
  vim.keymap.set("n", "[f", function()
    next_file(-1)
  end, opts)
  vim.keymap.set("n", "q", function()
    close_diff_wins()
    if job and job > 0 then
      pcall(vim.fn.jobstop, job)
    end
    for _, w in ipairs({ list_win, log_win }) do
      if w and vim.api.nvim_win_is_valid(w) then
        pcall(vim.api.nvim_win_close, w, true)
      end
    end
  end, opts)
end

map_review_keys(list_buf)
map_review_keys(log_buf)

vim.keymap.set("n", "<CR>", function()
  local l = vim.api.nvim_win_get_cursor(0)[1]
  local idx = l - 4 -- title + 2 help + blank
  if idx >= 1 and idx <= #touched then
    show_file(idx)
  end
end, { buffer = list_buf, nowait = true })

redraw_list()

local function send(obj)
  vim.fn.chansend(job, vim.json.encode(obj) .. "\n")
end

local function norm(p)
  return vim.fn.fnamemodify(p, ":p")
end

local function ensure_buf(path)
  local abs = norm(path)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= "" and norm(name) == abs then
        return b
      end
    end
  end
  vim.cmd("badd " .. vim.fn.fnameescape(abs))
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name ~= "" and norm(name) == abs then
      vim.fn.bufload(b)
      return b
    end
  end
  return nil
end

local function apply_replace(op)
  local path = op.path
  if type(path) ~= "string" then
    return false, "no path"
  end
  if not path:match("^/") then
    path = root .. "/" .. path
  end
  local rel = vim.fn.fnamemodify(path, ":.")
  local b = ensure_buf(path)
  if not b then
    return false, "no buffer"
  end
  if vim.api.nvim_buf_line_count(b) == 1 and vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == "" then
    vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.fn.readfile(path))
  end

  local old, new = op.old_text, op.new_text
  if type(old) ~= "string" or type(new) ~= "string" then
    return false, "missing old/new"
  end
  local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
  local text = table.concat(lines, "\n")
  local idx = text:find(old, 1, true)
  if not idx then
    local loose = old:gsub("^%s+", "")
    local li = text:find(loose, 1, true)
    if li then
      local line_start = text:sub(1, li):match(".*\n()") or 1
      local line_end = text:find("\n", li, true) or (#text + 1)
      old = text:sub(line_start, line_end - 1)
      idx = line_start
      local indent = old:match("^(%s*)") or ""
      new = indent .. new:gsub("^%s+", "")
    end
  end
  if not idx then
    return false, "old_text not found in " .. rel
  end

  local before = vim.deepcopy(lines)
  log("APPLY [" .. (#touched + 1) .. "] " .. rel)
  vim.wait(300)
  local replaced = text:sub(1, idx - 1) .. new .. text:sub(idx + #old)
  local new_lines = vim.split(replaced, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, new_lines)

  local changed_row = 1
  for i, line in ipairs(new_lines) do
    if before[i] ~= line then
      changed_row = i
      break
    end
  end

  table.insert(touched, {
    path = path,
    rel = rel,
    before = before,
    buf = b,
    changed_row = changed_row,
  })
  show_file(#touched)
  return true, "edited " .. rel
end

local tool_count = 0

local function on_msg(obj)
  local t = obj.type
  if t == "tool_execution_start" then
    tool_count = tool_count + 1
    log(string.format("pi TOOLCALL #%d: %s", tool_count, tostring(obj.toolName)))
    local a = obj.args or obj.input
    if a then
      log("  path=" .. tostring(a.path))
    end
    return
  end
  if t == "tool_execution_end" then
    log("pi TOOLCALL end isError=" .. tostring(obj.isError))
    return
  end
  if t == "agent_start" then
    log("pi agent_start")
    return
  end
  if t == "agent_end" then
    log("pi agent_end")
    if tool_count >= 3 and #touched >= 3 then
      log("READY: press a to accept (removes from list), r to reject")
      vim.notify("Review ready: a=accept r=reject ]f=next", vim.log.levels.INFO)
      show_file(1)
    else
      log(string.format("incomplete tools=%d touched=%d", tool_count, #touched))
    end
    return
  end
  if t == "extension_ui_request" and obj.method == "input" and obj.title == HOST_TITLE then
    local okj, op = pcall(vim.json.decode, obj.placeholder or "")
    if not okj then
      send({ type = "extension_ui_response", id = obj.id, value = "error:bad json" })
      return
    end
    local ok, result = apply_replace(op)
    send({
      type = "extension_ui_response",
      id = obj.id,
      value = ok and result or ("error:" .. tostring(result)),
    })
    log(ok and ("host OK: " .. tostring(result)) or ("host FAIL: " .. tostring(result)))
    return
  end
  if t == "response" and obj.command == "prompt" then
    log("prompt accepted=" .. tostring(obj.success))
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

log("starting pi…")
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
})

if not job or job <= 0 then
  log("FAIL: start pi")
  return
end

local prompt = table.concat({
  "Call nvim_replace_in_buffer exactly THREE times:",
  '1) path demo/mod_a.lua  old return "v1"  new return "v2-from-pi"',
  '2) path demo/mod_b.lua  old return "alpha"  new return "beta-from-pi"',
  "3) path demo/mod_c.lua  old return false  new return true -- flipped by pi",
  "Then reply DONE",
}, "\n")

vim.defer_fn(function()
  log("asking pi for 3 edits…")
  send({ id = "mf-1", type = "prompt", message = prompt })
end, 1000)

vim.notify("Multi-file review: a=accept (drop from list) r=reject", vim.log.levels.INFO)
redraw_log()
