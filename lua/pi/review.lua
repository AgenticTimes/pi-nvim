-- Multi-file review: pending list + BEFORE/AFTER diff + accept/reject
local config = require("pi.config")
local session = require("pi.session")

local M = {}
local file_idx = 0
local list_buf, list_win, before_win, code_win
local mapped = {}

local function close_diff()
  pcall(vim.cmd, "diffoff!")
  if before_win and vim.api.nvim_win_is_valid(before_win) then
    pcall(vim.api.nvim_win_close, before_win, true)
  end
  before_win = nil
end

local function redraw_list()
  if not list_buf or not vim.api.nvim_buf_is_valid(list_buf) then
    return
  end
  local touched = session.touched()
  local lines = {
    "pending (" .. #touched .. ")",
    "a accept · r reject",
    "]f/[f next/prev",
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
end

local function ensure_list()
  if list_buf and vim.api.nvim_buf_is_valid(list_buf) then
    return
  end
  list_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(list_buf, "pi://touched")
  vim.bo[list_buf].bufhidden = "hide"
end

local function map_keys(bufnr)
  if not bufnr or mapped[bufnr] or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  mapped[bufnr] = true
  local k = config.opts.keys
  local opts = { buffer = bufnr, nowait = true, silent = true }
  vim.keymap.set("n", k.accept, function()
    M.accept()
  end, opts)
  vim.keymap.set("n", k.reject, function()
    M.reject()
  end, opts)
  vim.keymap.set("n", k.next_file, function()
    M.next(1)
  end, opts)
  vim.keymap.set("n", k.prev_file, function()
    M.next(-1)
  end, opts)
end

local function show_empty()
  close_diff()
  file_idx = 0
  if code_win and vim.api.nvim_win_is_valid(code_win) then
    local empty = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(empty, 0, -1, false, { "No pending diffs." })
    vim.api.nvim_win_set_buf(code_win, empty)
  end
  redraw_list()
end

function M.open(idx)
  ensure_list()
  local touched = session.touched()
  if #touched == 0 then
    show_empty()
    return
  end
  idx = idx or file_idx
  if idx < 1 then
    idx = 1
  end
  if idx > #touched then
    idx = #touched
  end
  file_idx = idx
  local t = touched[idx]
  close_diff()

  -- ensure we have a code window: use current or create tab-ish split
  if not code_win or not vim.api.nvim_win_is_valid(code_win) then
    code_win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_set_current_win(code_win)
  vim.api.nvim_win_set_buf(code_win, t.buf)
  pcall(vim.api.nvim_set_option_value, "winbar", " AFTER " .. t.rel .. " [a]/[r] ", { win = code_win })

  if not list_win or not vim.api.nvim_win_is_valid(list_win) then
    vim.cmd("topleft 28vsplit")
    list_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(list_win, list_buf)
    vim.api.nvim_set_current_win(code_win)
  else
    vim.api.nvim_win_set_buf(list_win, list_buf)
  end

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

  vim.cmd("leftabove vsplit")
  before_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(before_win, before_buf)
  pcall(vim.api.nvim_set_option_value, "winbar", " BEFORE ", { win = before_win })
  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(code_win)
  vim.cmd("diffthis")
  pcall(vim.api.nvim_win_set_cursor, code_win, { t.changed_row or 1, 0 })

  map_keys(list_buf)
  map_keys(t.buf)
  map_keys(before_buf)
  redraw_list()
end

function M.next(delta)
  local n = #session.touched()
  if n == 0 then
    return
  end
  local i = file_idx + (delta or 1)
  if i < 1 then
    i = n
  elseif i > n then
    i = 1
  end
  M.open(i)
end

function M.accept()
  local touched = session.touched()
  if file_idx < 1 or file_idx > #touched then
    return false
  end
  local t = touched[file_idx]
  if config.opts.write_on_accept then
    pcall(vim.api.nvim_buf_call, t.buf, function()
      vim.cmd("silent! write")
    end)
  end
  session.remove_touched(file_idx)
  vim.notify("Accepted " .. t.rel, vim.log.levels.INFO)
  if #session.touched() == 0 then
    show_empty()
  else
    M.open(math.min(file_idx, #session.touched()))
  end
  return true
end

function M.reject()
  local touched = session.touched()
  if file_idx < 1 or file_idx > #touched then
    return false
  end
  local t = touched[file_idx]
  vim.api.nvim_buf_set_lines(t.buf, 0, -1, false, t.before)
  vim.bo[t.buf].modified = false
  session.remove_touched(file_idx)
  vim.notify("Rejected " .. t.rel, vim.log.levels.WARN)
  if #session.touched() == 0 then
    show_empty()
  else
    M.open(math.min(file_idx, #session.touched()))
  end
  return true
end

function M.close()
  close_diff()
  if list_win and vim.api.nvim_win_is_valid(list_win) then
    pcall(vim.api.nvim_win_close, list_win, true)
  end
  list_win = nil
end

function M.auto_show()
  local n = #session.touched()
  if n > 0 then
    M.open(n)
  end
end

function M.current_index()
  return file_idx
end

return M
