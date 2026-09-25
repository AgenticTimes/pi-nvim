-- Pure text / markdown helpers for chat rendering (no buffer state).
local M = {}

function M.disp_w(s)
  return vim.fn.strdisplaywidth(s or "")
end

--- Fill exactly `width` display cells with `ch` (ambiwidth-safe).
function M.rep_to_width(ch, width)
  if width <= 0 then
    return ""
  end
  local cw = M.disp_w(ch)
  if cw <= 0 then
    return string.rep(" ", width)
  end
  local n = math.floor(width / cw)
  local s = string.rep(ch, n)
  local got = n * cw
  if got < width then
    s = s .. string.rep(" ", width - got)
  end
  return s
end

--- Hard-wrap a line to `width` display cells.
function M.wrap_line(text, width, indent)
  if width < 8 or vim.fn.strdisplaywidth(text) <= width then
    return { text }
  end
  local out = {}
  local rest = text
  while vim.fn.strdisplaywidth(rest) > width do
    local i = vim.fn.strchars(rest)
    while i > 1 and vim.fn.strdisplaywidth(vim.fn.strcharpart(rest, 0, i)) > width do
      i = i - 1
    end
    out[#out + 1] = vim.fn.strcharpart(rest, 0, i)
    rest = (indent or "") .. vim.fn.strcharpart(rest, i)
  end
  out[#out + 1] = rest
  return out
end

--- Cap a list of lines, keeping the head and summarizing the dropped tail.
function M.cap_lines(lines, max)
  if #lines <= max then
    return lines
  end
  local out = {}
  for i = 1, max - 1 do
    out[i] = lines[i]
  end
  out[max] = string.format("… +%d lines", #lines - max + 1)
  return out
end

--- Markdown table row (optional leading gutter spaces).
--- Require ≥2 pipes so a lone "|" mid-stream is not treated as a finished row.
function M.is_md_table_row(s)
  local t = vim.trim(s or "")
  if t == "" or t:sub(1, 1) ~= "|" or t:sub(-1) ~= "|" then
    return false
  end
  local n = 0
  for _ in t:gmatch("|") do
    n = n + 1
  end
  return n >= 2
end

function M.split_md_cells(s)
  local t = vim.trim(s or "")
  t = t:gsub("^|", ""):gsub("|$", "")
  local cells = vim.split(t, "|", { plain = true })
  for i, c in ipairs(cells) do
    cells[i] = vim.trim(c)
  end
  return cells
end

function M.is_md_sep_row(cells)
  if #cells == 0 then
    return false
  end
  for _, c in ipairs(cells) do
    if c ~= "" and not c:match("^:?%-+:?$") then
      return false
    end
  end
  return true
end

local function pad_md_cell(text, width)
  local w = M.disp_w(text)
  if w >= width then
    return text
  end
  return text .. string.rep(" ", width - w)
end

local function format_md_sep(cell, width)
  local left = cell:sub(1, 1) == ":"
  local right = #cell > 0 and cell:sub(-1) == ":"
  local inner = width - (left and 1 or 0) - (right and 1 or 0)
  inner = math.max(3, inner)
  return (left and ":" or "-") .. string.rep("-", math.max(0, inner - 1)) .. (right and ":" or "")
end

--- Pad markdown table columns to equal display width (CJK-safe).
function M.align_md_table(raw_lines)
  local rows = {}
  for _, line in ipairs(raw_lines) do
    rows[#rows + 1] = M.split_md_cells(line)
  end
  local ncols = 0
  for _, r in ipairs(rows) do
    ncols = math.max(ncols, #r)
  end
  if ncols == 0 then
    return raw_lines
  end
  local widths = {}
  for c = 1, ncols do
    widths[c] = 3
  end
  for _, r in ipairs(rows) do
    if not M.is_md_sep_row(r) then
      for c = 1, ncols do
        widths[c] = math.max(widths[c], M.disp_w(r[c] or ""))
      end
    end
  end
  local out = {}
  for _, r in ipairs(rows) do
    local parts = {}
    local sep = M.is_md_sep_row(r)
    for c = 1, ncols do
      local cell = r[c] or ""
      if sep then
        parts[c] = format_md_sep(cell == "" and "---" or cell, widths[c])
      else
        parts[c] = pad_md_cell(cell, widths[c])
      end
    end
    out[#out + 1] = "| " .. table.concat(parts, " | ") .. " |"
  end
  return out
end

return M
