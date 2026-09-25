-- Tool-call line formatting and collapse (no buffer / bubble state).
local text = require("pi.render.text")

local M = {}

M.FULL_CAP = 80
M.COLLAPSE_BODY = 3
M.COLLAPSE_ERR_BODY = 6

local MAX_ARG_CHARS = 2000

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

--- Collapsed tool box: header + a few body lines; expand via za / <CR>.
function M.collapse_tool_lines(full, expanded, has_err)
  full = full or {}
  if expanded or #full <= 1 then
    return full
  end
  local body_keep = has_err and M.COLLAPSE_ERR_BODY or M.COLLAPSE_BODY
  local keep = math.min(1 + body_keep, #full)
  if keep >= #full then
    return full
  end
  local out = {}
  for i = 1, keep do
    out[i] = full[i]
  end
  out[#out + 1] = string.format("  … +%d lines  za expand", #full - keep)
  return out
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
