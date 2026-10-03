-- Tool-call line formatting and collapse (no buffer / bubble state).
local text = require("pi.render.text")

local M = {}

M.FULL_CAP = 80
M.COLLAPSE_BODY = 3
M.COLLAPSE_ERR_BODY = 6

local MAX_ARG_CHARS = 2000
local COLLAPSE_COL = 56

function M.short_name(name)
  name = tostring(name or "?")
  return name:gsub("^nvim_", "")
end

--- Cap one argument value so a whole file (write/edit content) cannot be
--- rendered into the chat.
local function clip(s)
  if vim.fn.strchars(s) <= MAX_ARG_CHARS then
    return s
  end
  return vim.fn.strcharpart(s, 0, MAX_ARG_CHARS) .. " …"
end

local function trunc_disp(s, cols)
  cols = cols or COLLAPSE_COL
  s = tostring(s or "")
  if vim.fn.strdisplaywidth(s) <= cols then
    return s
  end
  return vim.fn.strcharpart(s, 0, math.max(1, cols - 1)) .. "…"
end

--- Collapsed tool box: header + one preview arg line + fold marker.
--- Preview keeps the command/path visible so a folded `bash ✓` still answers
--- "what did it do?" without expanding.
--- Edit tools that already embed a mini-diff keep the whole block (Cursor-style).
function M.collapse_tool_lines(full, expanded, has_err)
  full = full or {}
  if expanded or #full == 0 then
    return full
  end
  -- Mini-diff bodies (chrome holds path / <C-r>) must stay expanded when folded.
  local has_diff = false
  for i = 1, #full do
    local s = full[i]
    if type(s) == "string" and (s:sub(1, 2) == "+ " or s:sub(1, 2) == "- ") then
      has_diff = true
      break
    end
  end
  if has_diff then
    return full
  end
  local header = trunc_disp(full[1], 64)
  if #full == 1 then
    if header == full[1] then
      return full
    end
    return { header, "  … ftt to expand" }
  end
  local preview = trunc_disp(full[2], 72)
  local hidden = #full - 2
  if hidden <= 0 then
    return { header, preview }
  end
  return {
    header,
    preview,
    string.format("  … +%d lines  ftt to expand", hidden),
  }
end

--- Host buffer edit tools that have a before/after snapshot in session.touched.
function M.is_buffer_edit(name, args)
  local n = M.short_name(name):lower()
  if n:find("replace", 1, true) or n:find("write", 1, true) or n == "edit" then
    return true
  end
  if type(args) == "table" and (args.old_text ~= nil or args.new_text ~= nil) and args.path then
    return true
  end
  return false
end

--- First differing hunk as Cursor-style truncated +/- lines (already indented).
--- @return string[] lines, integer hidden_count
function M.mini_diff_lines(before, after, max_body)
  before = before or {}
  after = after or {}
  max_body = max_body or 8
  local n = math.max(#before, #after)
  local first
  for i = 1, n do
    if (before[i] or "") ~= (after[i] or "") then
      first = i
      break
    end
  end
  if not first then
    return { "  (no text change)" }, 0
  end
  local ctx = 1
  local s = math.max(1, first - ctx)
  local e = first
  while e < n and ((before[e + 1] or "") ~= (after[e + 1] or "")) do
    e = e + 1
  end
  e = math.min(n, e + ctx)

  local out = {}
  local function push(kind, line)
    out[#out + 1] = trunc_disp(kind .. tostring(line or ""), 76)
  end
  for i = s, e do
    local b, a = before[i], after[i]
    if b ~= nil and a ~= nil and b == a then
      push("  ", b)
    else
      if b ~= nil then
        push("- ", b)
      end
      if a ~= nil and a ~= b then
        push("+ ", a)
      end
    end
  end
  local hidden = 0
  for i = 1, n do
    if (i < s or i > e) and (before[i] or "") ~= (after[i] or "") then
      hidden = hidden + 1
    end
  end
  if #out > max_body then
    hidden = hidden + (#out - max_body)
    local trimmed = {}
    for i = 1, max_body do
      trimmed[i] = out[i]
    end
    out = trimmed
  end
  return out, hidden
end

--- Lines for an edit tool body: only the mini-diff (path / <C-r> live in the
--- top rule chrome, not in the body).
function M.edit_diff_lines(rel, before, after)
  local out = {}
  local body, hidden = M.mini_diff_lines(before, after, 8)
  for _, l in ipairs(body) do
    out[#out + 1] = l
  end
  if hidden > 0 then
    out[#out + 1] = string.format("  … +%d", hidden)
  end
  if #out == 0 then
    out[1] = "  (no text change)"
  end
  return out
end

--- Collapsed thinking box (default expanded; ftk toggles).
function M.collapse_thinking_lines(full, expanded)
  full = full or {}
  if expanded or #full == 0 then
    return full
  end
  local header = trunc_disp(full[1], 64)
  if #full == 1 then
    if header == full[1] then
      return full
    end
    return { header, "  … ftk to expand" }
  end
  return {
    header,
    string.format("  … +%d lines  ftk to expand", #full - 1),
  }
end

--- The arguments a tool was actually called with.
function M.tool_arg_lines(args)
  local out = {}
  if type(args) ~= "table" then
    return out
  end
  local function push(prefix, value)
    local parts = vim.split(clip(tostring(value)), "\n", { plain = true })
    out[#out + 1] = prefix .. parts[1]
    for i = 2, #parts do
      out[#out + 1] = "  " .. parts[i]
    end
  end
  if args.command ~= nil then
    push("$ ", args.command)
  end
  local keys = {}
  for k in pairs(args) do
    if k ~= "command" then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = args[k]
    if type(v) == "table" then
      v = vim.json.encode(v)
    end
    if v ~= nil and tostring(v) ~= "" then
      push(tostring(k) .. ": ", v)
    end
  end
  return text.cap_lines(out, 12)
end

--- One tool call as full lines (caller collapses for display).
--- `wrap_width` is the max display width for each line.
function M.tool_block_lines(name, args, ok, count, err, wrap_width)
  local mark = ok == nil and "…" or (ok and "✓" or "✗")
  local head = string.format("⚙ %s %s", M.short_name(name), mark)
  if count and count > 1 then
    head = head .. string.format(" ×%d", count)
  end
  local raw = { head }
  for _, l in ipairs(M.tool_arg_lines(args)) do
    raw[#raw + 1] = "  " .. l
  end
  if err and err ~= "" then
    for _, l in ipairs(text.cap_lines(vim.split(err, "\n", { plain = true }), 6)) do
      raw[#raw + 1] = "  ! " .. l
    end
  end
  local width = math.max(20, wrap_width or 40)
  local lines = {}
  for _, l in ipairs(raw) do
    for _, w in ipairs(text.wrap_line(l, width, "  ")) do
      lines[#lines + 1] = w
    end
  end
  return text.cap_lines(lines, M.FULL_CAP)
end

return M
