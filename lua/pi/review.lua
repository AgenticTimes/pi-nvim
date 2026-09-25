-- Multi-file review: pending list + BEFORE/AFTER diff + accept/reject
local config = require("pi.config")
local session = require("pi.session")

local M = {}
local file_idx = 0
local list_buf, list_win, before_win, code_win
local mapped = {}
local hint_ns = vim.api.nvim_create_namespace("pi_review_hint")
local hint_buf ---@type integer|nil

local function clear_hint()
  if hint_buf and vim.api.nvim_buf_is_valid(hint_buf) then
    pcall(vim.api.nvim_buf_clear_namespace, hint_buf, hint_ns, 0, -1)
  end
  hint_buf = nil
end

--- First differing 1-based row between AFTER buffer lines and BEFORE snapshot.
local function first_hunk_row(after, before)
  local n = math.max(#after, #before)
  for i = 1, n do
    if (after[i] or "") ~= (before[i] or "") then
      return i
    end
  end
  return nil
end

--- One hint above the first changed hunk (not every hunk).
local function paint_hint(buf, before_lines)
  clear_hint()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local after = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local row = first_hunk_row(after, before_lines or {})
  if not row then
    return
  end
  if vim.fn.hlexists("PiReview") == 0 then
    vim.api.nvim_set_hl(0, "PiReview", { fg = 0xe0af68, bold = true })
  end
  local text = " a accept · r reject · ah/rh hunk · ]h/[h · q close "
  pcall(vim.api.nvim_buf_set_extmark, buf, hint_ns, row - 1, 0, {
    virt_lines = { { { text, "PiReview" } } },
    virt_lines_above = true,
    priority = 200,
  })
  hint_buf = buf
end

local function close_diff()
  clear_hint()
  pcall(vim.cmd, "diffoff!")
  if before_win and vim.api.nvim_win_is_valid(before_win) then
    pcall(vim.api.nvim_win_close, before_win, true)
  end
  before_win = nil
end

--- Tear down review chrome (before split + pending list). Keep code_win on prefer_buf when given.
function M.close(prefer_buf)
  close_diff()
  if list_win and vim.api.nvim_win_is_valid(list_win) then
    pcall(vim.api.nvim_win_close, list_win, true)
  end
  list_win = nil
  file_idx = 0
  if code_win and vim.api.nvim_win_is_valid(code_win) then
    pcall(vim.api.nvim_set_option_value, "winbar", "", { win = code_win })
    if prefer_buf and vim.api.nvim_buf_is_valid(prefer_buf) then
      pcall(vim.api.nvim_win_set_buf, code_win, prefer_buf)
      pcall(vim.api.nvim_set_current_win, code_win)
    end
  end
end

--- Queue empty: close review UI instead of a "No pending diffs" scratch that needs :q.
local function finish_empty(prefer_buf)
  M.close(prefer_buf)
end

local function redraw_list()
  if not list_buf or not vim.api.nvim_buf_is_valid(list_buf) then
    return
  end
  local touched = session.touched()
  local lines = {
    "pending (" .. #touched .. ")",
    "a accept · r reject · ah/rh hunk · ]h/[h · :PiAcceptAll / :PiRejectAll",
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
  local existing = vim.fn.bufnr("pi://touched")
  if existing > 0 then
    if vim.api.nvim_buf_is_valid(existing) then
      list_buf = existing
      return
    end
    -- wiped but name reserved → force delete so we can recreate
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end
  list_buf = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, list_buf, "pi://touched")
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
  vim.keymap.set("n", "ah", function()
    M.accept_hunk()
  end, opts)
  vim.keymap.set("n", "rh", function()
    M.reject_hunk()
  end, opts)
  vim.keymap.set("n", "]h", function()
    M.next_hunk(1)
  end, opts)
  vim.keymap.set("n", "[h", function()
    M.next_hunk(-1)
  end, opts)
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)
end

function M.open(idx)
  ensure_list()
  local touched = session.touched()
  if #touched == 0 then
    finish_empty()
    vim.notify("pi: no pending diffs", vim.log.levels.INFO)
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
    if before_buf > 0 then
      pcall(vim.api.nvim_buf_delete, before_buf, { force = true })
    end
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
  paint_hint(t.buf, t.before)
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
    finish_empty(t.buf)
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
    finish_empty(t.buf)
  else
    M.open(math.min(file_idx, #session.touched()))
  end
  return true
end

function M.accept_all()
  while #session.touched() > 0 do
    file_idx = 1
    if not M.accept() then
      break
    end
  end
end

function M.reject_all()
  while #session.touched() > 0 do
    file_idx = 1
    if not M.reject() then
      break
    end
  end
end

--- Find contiguous changed region around cursor in AFTER buffer vs BEFORE snapshot
local function hunk_range(after_lines, before_lines, cursor_row)
  local n = math.max(#after_lines, #before_lines)
  local row = math.min(math.max(1, cursor_row), n)
  local function differs(i)
    return (after_lines[i] or "") ~= (before_lines[i] or "")
  end
  if not differs(row) then
    -- scan nearby
    local found
    for d = 0, n do
      if differs(row + d) then
        found = row + d
        break
      end
      if d > 0 and differs(row - d) then
        found = row - d
        break
      end
    end
    if not found then
      return nil
    end
    row = found
  end
  local s, e = row, row
  while s > 1 and differs(s - 1) do
    s = s - 1
  end
  while e < n and differs(e + 1) do
    e = e + 1
  end
  return s, e
end

--- Accept current hunk: fold AFTER into BEFORE snapshot so later reject keeps it
function M.accept_hunk()
  local touched = session.touched()
  if file_idx < 1 or file_idx > #touched then
    return false
  end
  local t = touched[file_idx]
  local after = vim.api.nvim_buf_get_lines(t.buf, 0, -1, false)
  local cur = 1
  if code_win and vim.api.nvim_win_is_valid(code_win) then
    cur = vim.api.nvim_win_get_cursor(code_win)[1]
  end
  local s, e = hunk_range(after, t.before, cur)
  if not s then
    vim.notify("pi: no hunk under cursor", vim.log.levels.INFO)
    return false
  end
  local before = vim.deepcopy(t.before)
  for i = s, e do
    before[i] = after[i]
  end
  -- grow before if after longer
  for i = #before + 1, #after do
    before[i] = after[i]
  end
  t.before = before
  vim.notify(string.format("Accepted hunk %d-%d in %s", s, e, t.rel), vim.log.levels.INFO)
  M.open(file_idx)
  return true
end

--- Reject current hunk: restore BEFORE lines into AFTER buffer
function M.reject_hunk()
  local touched = session.touched()
  if file_idx < 1 or file_idx > #touched then
    return false
  end
  local t = touched[file_idx]
  local after = vim.api.nvim_buf_get_lines(t.buf, 0, -1, false)
  local cur = 1
  if code_win and vim.api.nvim_win_is_valid(code_win) then
    cur = vim.api.nvim_win_get_cursor(code_win)[1]
  end
  local s, e = hunk_range(after, t.before, cur)
  if not s then
    vim.notify("pi: no hunk under cursor", vim.log.levels.INFO)
    return false
  end
  local new_after = vim.deepcopy(after)
  for i = s, e do
    new_after[i] = t.before[i]
  end
  -- trim if before shorter in trailing hunk
  if e == #after and #t.before < #after then
    while #new_after > #t.before do
      table.remove(new_after)
    end
  end
  vim.api.nvim_buf_set_lines(t.buf, 0, -1, false, new_after)
  -- if file matches before entirely, drop from pending
  local same = true
  local final = vim.api.nvim_buf_get_lines(t.buf, 0, -1, false)
  if #final ~= #t.before then
    same = false
  else
    for i = 1, #final do
      if final[i] ~= t.before[i] then
        same = false
        break
      end
    end
  end
  if same then
    session.remove_touched(file_idx)
    vim.notify("Rejected last hunk; removed " .. t.rel, vim.log.levels.WARN)
    if #session.touched() == 0 then
      finish_empty(t.buf)
    else
      M.open(math.min(file_idx, #session.touched()))
    end
  else
    vim.notify(string.format("Rejected hunk %d-%d in %s", s, e, t.rel), vim.log.levels.WARN)
    M.open(file_idx)
  end
  return true
end

--- Jump to next/prev differing hunk in current pending file
function M.next_hunk(dir)
  dir = dir or 1
  local touched = session.touched()
  if file_idx < 1 or file_idx > #touched then
    return false
  end
  local t = touched[file_idx]
  local after = vim.api.nvim_buf_get_lines(t.buf, 0, -1, false)
  local before = t.before
  local n = math.max(#after, #before)
  local function differs(i)
    return (after[i] or "") ~= (before[i] or "")
  end
  -- collect hunk starts
  local starts = {}
  local i = 1
  while i <= n do
    if differs(i) then
      table.insert(starts, i)
      while i <= n and differs(i) do
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  if #starts == 0 then
    vim.notify("pi: no hunks", vim.log.levels.INFO)
    return false
  end
  local cur = 1
  if code_win and vim.api.nvim_win_is_valid(code_win) then
    cur = vim.api.nvim_win_get_cursor(code_win)[1]
  end
  local target
  if dir > 0 then
    for _, s in ipairs(starts) do
      if s > cur then
        target = s
        break
      end
    end
    target = target or starts[1]
  else
    for j = #starts, 1, -1 do
      if starts[j] < cur then
        target = starts[j]
        break
      end
    end
    target = target or starts[#starts]
  end
  if code_win and vim.api.nvim_win_is_valid(code_win) then
    pcall(vim.api.nvim_win_set_cursor, code_win, { target, 0 })
    vim.api.nvim_set_current_win(code_win)
  end
  return true
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
