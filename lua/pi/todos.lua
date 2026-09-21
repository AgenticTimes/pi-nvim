-- Open todos from the pi todos extension (files, not RPC).
-- Default dir: <cwd>/.pi/todos, or PI_TODO_PATH (absolute or relative to cwd).
local M = {}

local function json_object_end(s)
  if s:sub(1, 1) ~= "{" then
    return nil
  end
  local depth = 0
  local in_str = false
  local esc = false
  for i = 1, #s do
    local c = s:sub(i, i)
    if in_str then
      if esc then
        esc = false
      elseif c == "\\" then
        esc = true
      elseif c == '"' then
        in_str = false
      end
    elseif c == '"' then
      in_str = true
    elseif c == "{" then
      depth = depth + 1
    elseif c == "}" then
      depth = depth - 1
      if depth == 0 then
        return i
      end
    end
  end
  return nil
end

function M.dir(cwd)
  cwd = cwd or vim.fn.getcwd()
  local override = vim.env.PI_TODO_PATH
  if type(override) == "string" and override:match("%S") then
    override = vim.trim(override)
    if override:sub(1, 1) == "/" then
      return override
    end
    return cwd .. "/" .. override
  end
  return cwd .. "/.pi/todos"
end

local function closed(status)
  status = (status or "open"):lower()
  return status == "closed" or status == "done"
end

--- Parse one todo markdown file. Returns nil when closed/done or unreadable.
function M.parse_file(path, id_fallback)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    return nil
  end
  local content = table.concat(lines, "\n")
  local front = ""
  local end_i = json_object_end(content)
  if end_i then
    front = content:sub(1, end_i)
  end
  local data = {}
  if front ~= "" then
    local decoded_ok, decoded = pcall(vim.json.decode, front)
    if decoded_ok and type(decoded) == "table" then
      data = decoded
    end
  end
  local status = data.status
  if type(status) ~= "string" or status == "" then
    status = "open"
  end
  if closed(status) then
    return nil
  end
  local id = id_fallback
  if type(data.id) == "string" and data.id ~= "" then
    id = data.id
  end
  local title = type(data.title) == "string" and data.title or ""
  local assigned = type(data.assigned_to_session) == "string" and data.assigned_to_session or ""
  local created = type(data.created_at) == "string" and data.created_at or ""
  return {
    id = id,
    title = title,
    status = status,
    assigned = assigned,
    created_at = created,
  }
end

function M.list_dir(dir)
  local out = {}
  if not dir or vim.fn.isdirectory(dir) ~= 1 then
    return out
  end
  local names = vim.fn.readdir(dir)
  for _, name in ipairs(names) do
    if name:sub(-3) == ".md" then
      local id = name:sub(1, -4)
      local item = M.parse_file(dir .. "/" .. name, id)
      if item then
        out[#out + 1] = item
      end
    end
  end
  table.sort(out, function(a, b)
    local aa = a.assigned ~= ""
    local bb = b.assigned ~= ""
    if aa ~= bb then
      return aa
    end
    return a.created_at < b.created_at
  end)
  return out
end

function M.list(cwd)
  return M.list_dir(M.dir(cwd))
end

function M.lines(items)
  local n = items and #items or 0
  local lines = { string.format("Todos  %d", n) }
  if n == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "—"
    return lines
  end
  for _, t in ipairs(items) do
    local mark = t.assigned ~= "" and "▸" or "·"
    local title = (t.title ~= "" and t.title or "(untitled)"):gsub("%s+", " ")
    lines[#lines + 1] = mark .. " " .. title
  end
  return lines
end

return M
