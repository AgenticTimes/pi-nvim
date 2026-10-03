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

local function status_mark(ok)
  if ok == nil then
    return "…"
  end
  return ok and "✓" or "✗"
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

--- Preferred arg keys for a one-line chrome summary (first hit wins).
local SUMMARY_KEYS = {
  "path",
  "file",
  "filename",
  "command",
  "pattern",
  "regexp",
  "query",
  "agent",
  "message",
  "prompt",
  "task",
  "description",
  "goal",
  "url",
  "uri",
  "id",
  "name",
  "label",
}

--- Pick (key, value) for the top-rule summary. Prefer known keys, else first
--- short non-table string by sorted key name.
---@return string|nil, any
local function pick_summary_arg(args)
  if type(args) ~= "table" then
    return nil, nil
  end
  for _, k in ipairs(SUMMARY_KEYS) do
    local v = args[k]
    if v ~= nil and type(v) ~= "table" and tostring(v) ~= "" then
      return k, v
    end
  end
  local keys = {}
  for k, v in pairs(args) do
    if type(v) ~= "table" and tostring(v) ~= "" then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)
  if keys[1] then
    return keys[1], args[keys[1]]
  end
  return nil, nil
end

local function one_line(v)
  local s = tostring(v):match("^[^\n]+") or tostring(v)
  return (s:gsub("%s+", " "):match("^%s*(.-)%s*$")) or ""
end

local function pathish(key)
  return key == "path" or key == "file" or key == "filename"
end

--- One-line summary for the top-rule label.
--- nil only for edit/write (those keep path + mini-diff via apply_edit_chrome).
--- Every other tool always gets a chrome summary — never a bare "toolcall".
function M.chrome_label(name, args, ok, count)
  if M.is_buffer_edit(name, args) then
    return nil
  end
  local n = M.short_name(name):lower()
  args = type(args) == "table" and args or {}
  local mark = status_mark(ok)
  local suffix = " " .. mark
  if count and count > 1 then
    suffix = suffix .. string.format(" ×%d", count)
  end

  if n:find("subagent", 1, true) then
    local agent = args.agent or args.name or args.label or "worker"
    local label = "subagent · " .. trunc_disp(tostring(agent), 18)
    local task = args.task or args.prompt or args.description or args.goal
    if task and tostring(task) ~= "" then
      local one = one_line(task)
      local room = 42 - vim.fn.strdisplaywidth(label)
      if room > 10 and one ~= "" then
        label = label .. " · " .. trunc_disp(one, room)
      end
    end
    return label .. suffix
  end

  if n == "bash" or n == "shell" or n == "run" then
    local cmd = args.command
    if cmd and tostring(cmd) ~= "" then
      return trunc_disp("$ " .. one_line(cmd), 44) .. suffix
    end
  end

  if args.path
    and (
      n:find("read", 1, true)
      or n:find("grep", 1, true)
      or n:find("glob", 1, true)
      or n:find("search", 1, true)
    )
  then
    local p = tostring(args.path)
    if vim.fn.strdisplaywidth(p) > 24 then
      p = vim.fn.fnamemodify(p, ":t")
    end
    local extra = args.pattern or args.regexp or args.query
    if extra and tostring(extra) ~= "" then
      return trunc_disp(p .. " · " .. tostring(extra), 40) .. suffix
    end
    return trunc_disp(n .. " · " .. p, 40) .. suffix
  end

  -- Universal fallback: {name} · {best arg} (or just {name}).
  local key, val = pick_summary_arg(args)
  if not key then
    return trunc_disp(n, 40) .. suffix
  end
  local one = one_line(val)
  if pathish(key) and vim.fn.strdisplaywidth(one) > 24 then
    one = vim.fn.fnamemodify(one, ":t")
  end
  return trunc_disp(n .. " · " .. one, 44) .. suffix
end

--- Arg keys already shown on the chrome label — omit from the body.
function M.chrome_omit_keys(name, args)
  local n = M.short_name(name):lower()
  args = type(args) == "table" and args or {}
  local omit = {}
  if n:find("subagent", 1, true) then
    omit.agent = true
    omit.name = true
    omit.label = true
    local task = args.task or args.prompt or args.description or args.goal
    if task and vim.fn.strdisplaywidth(tostring(task):gsub("%s+", " ")) <= 24 then
      omit.task = true
      omit.prompt = true
      omit.description = true
      omit.goal = true
    end
  elseif n == "bash" or n == "shell" or n == "run" then
    -- One-line commands live entirely on chrome; multi-line keep body for expand.
    local cmd = args.command
    if cmd and not tostring(cmd):find("\n", 1, true) then
      omit.command = true
    end
  elseif args.path
    and (
      n:find("read", 1, true)
      or n:find("grep", 1, true)
      or n:find("glob", 1, true)
      or n:find("search", 1, true)
    )
  then
    omit.path = true
    if args.pattern or args.regexp or args.query then
      omit.pattern = true
      omit.regexp = true
      omit.query = true
    end
  else
    local key, val = pick_summary_arg(args)
    if key and val and not tostring(val):find("\n", 1, true) then
      local one = one_line(val)
      if vim.fn.strdisplaywidth(one) <= 36 then
        omit[key] = true
      end
    end
  end
  return omit
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
  -- Chrome-summary tools: spacer-only body folds to a single blank row.
  if full[1] == "" and not has_err then
    if #full == 1 then
      return { "" }
    end
    local preview = trunc_disp(full[2], 72)
    local hidden = #full - 2
    if hidden <= 0 then
      return { preview }
    end
    return {
      preview,
      string.format("  … +%d lines  ftt to expand", hidden),
    }
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
---@param omit table|nil set of keys to skip (already on chrome)
function M.tool_arg_lines(args, omit)
  local out = {}
  if type(args) ~= "table" then
    return out
  end
  omit = omit or {}
  local function push(prefix, value)
    local parts = vim.split(clip(tostring(value)), "\n", { plain = true })
    out[#out + 1] = prefix .. parts[1]
    for i = 2, #parts do
      out[#out + 1] = "  " .. parts[i]
    end
  end
  if args.command ~= nil and not omit.command then
    push("$ ", args.command)
  end
  local keys = {}
  for k in pairs(args) do
    if k ~= "command" and not omit[k] then
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
--- When chrome_label applies, body skips the ⚙ header and omitted keys.
function M.tool_block_lines(name, args, ok, count, err, wrap_width)
  local chrome = M.chrome_label(name, args, ok, count)
  local raw = {}
  if chrome then
    local omit = M.chrome_omit_keys(name, args)
    for _, l in ipairs(M.tool_arg_lines(args, omit)) do
      raw[#raw + 1] = "  " .. l
    end
    if err and err ~= "" then
      for _, l in ipairs(text.cap_lines(vim.split(err, "\n", { plain = true }), 6)) do
        raw[#raw + 1] = "  ! " .. l
      end
    end
    if #raw == 0 then
      raw[1] = ""
    end
  else
    local mark = status_mark(ok)
    local head = string.format("⚙ %s %s", M.short_name(name), mark)
    if count and count > 1 then
      head = head .. string.format(" ×%d", count)
    end
    raw[1] = head
    for _, l in ipairs(M.tool_arg_lines(args)) do
      raw[#raw + 1] = "  " .. l
    end
    if err and err ~= "" then
      for _, l in ipairs(text.cap_lines(vim.split(err, "\n", { plain = true }), 6)) do
        raw[#raw + 1] = "  ! " .. l
      end
    end
  end
  local width = math.max(20, wrap_width or 40)
  local lines = {}
  for _, l in ipairs(raw) do
    if l == "" then
      lines[#lines + 1] = ""
    else
      for _, w in ipairs(text.wrap_line(l, width, "  ")) do
        lines[#lines + 1] = w
      end
    end
  end
  return text.cap_lines(lines, M.FULL_CAP)
end

return M
