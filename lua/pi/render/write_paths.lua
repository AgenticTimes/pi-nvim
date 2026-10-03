-- Parse write targets from tool args and snapshot disk lines for mini-diff.
local M = {}

local SKIP = {
  ["/dev/null"] = true,
  ["/dev/stdout"] = true,
  ["/dev/stderr"] = true,
  ["-"] = true,
}

local function looks_like_path(p)
  if type(p) ~= "string" or p == "" then
    return false
  end
  if SKIP[p] then
    return false
  end
  -- Skip fd redirects, flags (-a), shell variables / globs we cannot resolve.
  if p:match("^&") or p:match("^%-") or p:match("^%$") or p:find("*", 1, true) or p:find("?", 1, true) then
    return false
  end
  return true
end

function M.norm(path)
  path = tostring(path or "")
  if path == "" then
    return nil
  end
  if not path:match("^/") and not path:match("^~") then
    path = vim.fn.getcwd() .. "/" .. path
  end
  return vim.fn.fnamemodify(path, ":p")
end

function M.rel(path)
  local abs = M.norm(path)
  if not abs then
    return nil
  end
  return vim.fn.fnamemodify(abs, ":.")
end

function M.read_lines(path)
  local abs = M.norm(path)
  if not abs then
    return {}
  end
  if vim.fn.filereadable(abs) ~= 1 then
    return {}
  end
  local ok, lines = pcall(vim.fn.readfile, abs)
  if not ok or type(lines) ~= "table" then
    return {}
  end
  return lines
end

local function push_unique(out, seen, path)
  if not looks_like_path(path) then
    return
  end
  local abs = M.norm(path)
  if not abs or seen[abs] then
    return
  end
  seen[abs] = true
  out[#out + 1] = abs
end

--- Extract write targets from a bash command (best-effort).
function M.bash_write_paths(command)
  local out, seen = {}, {}
  command = tostring(command or "")
  if command == "" then
    return out
  end

  -- cat > path <<…  /  cat >> path <<…
  for path in command:gmatch("cat%s+>>?%s*([%w%._%-/%~]+)%s*<<") do
    push_unique(out, seen, path)
  end
  for path in command:gmatch("cat%s+>>?%s*['\"]([^'\"]+)['\"]%s*<<") do
    push_unique(out, seen, path)
  end

  -- tee / tee -a
  for path in command:gmatch("tee%s+%-a%s+['\"]([^'\"]+)['\"]") do
    push_unique(out, seen, path)
  end
  for path in command:gmatch("tee%s+%-a%s+([%w%._%-/%~]+)") do
    push_unique(out, seen, path)
  end
  for path in command:gmatch("tee%s+['\"]([^'\"]+)['\"]") do
    push_unique(out, seen, path)
  end
  for path in command:gmatch("tee%s+([%w%._%-/%~]+)") do
    push_unique(out, seen, path)
  end

  -- Generic > / >> targets (last resort; skip >&)
  for op, path in command:gmatch("(>>?)%s*['\"]([^'\"]+)['\"]") do
    if op then
      push_unique(out, seen, path)
    end
  end
  for op, path in command:gmatch("(>>?)%s*([%w%._%-/%~]+)") do
    if op and not path:match("^&") then
      push_unique(out, seen, path)
    end
  end

  return out
end

--- Paths this tool is likely to write.
function M.extract_write_paths(name, args)
  local out, seen = {}, {}
  local n = tostring(name or ""):gsub("^nvim_", ""):lower()
  args = type(args) == "table" and args or {}

  if args.path and (n:find("replace", 1, true) or n:find("write", 1, true) or n == "edit") then
    push_unique(out, seen, args.path)
  elseif type(args.old_text) == "string" and type(args.new_text) == "string" and args.path then
    push_unique(out, seen, args.path)
  end

  if n == "bash" or n == "shell" or n == "run" then
    for _, p in ipairs(M.bash_write_paths(args.command)) do
      push_unique(out, seen, p)
    end
  end

  return out
end

--- Snapshot disk contents before the tool runs.
---@return { path: string, rel: string, before: string[] }[]
function M.snapshot_writes(name, args)
  local snaps = {}
  for _, abs in ipairs(M.extract_write_paths(name, args)) do
    snaps[#snaps + 1] = {
      path = abs,
      rel = M.rel(abs) or abs,
      before = M.read_lines(abs),
    }
  end
  return snaps
end

local function lines_equal(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

--- First snapshot whose on-disk content changed.
---@return { path: string, rel: string, before: string[], after: string[] }|nil
function M.first_changed(snapshots)
  for _, s in ipairs(snapshots or {}) do
    local after = M.read_lines(s.path)
    if not lines_equal(s.before or {}, after) then
      return {
        path = s.path,
        rel = s.rel or M.rel(s.path) or s.path,
        before = s.before or {},
        after = after,
      }
    end
  end
  return nil
end

return M
