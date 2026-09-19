-- Discover + switch pi sessions on disk (~/.pi/agent/sessions/--cwd--/)
local M = {}

local function agent_dir()
  return vim.fn.expand("~/.pi/agent")
end

--- Match pi getDefaultSessionDirPath encoding
function M.session_dir_for(cwd)
  cwd = vim.fn.fnamemodify(cwd or vim.fn.getcwd(), ":p")
  cwd = cwd:gsub("/+$", "")
  local safe = cwd:gsub("^[/\\]+", ""):gsub("[/\\:]", "-")
  return agent_dir() .. "/sessions/--" .. safe .. "--"
end

local function peek_meta(path)
  local name, first_user
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local n = 0
  for line in f:lines() do
    n = n + 1
    if n > 40 then
      break
    end
    local ok, obj = pcall(vim.json.decode, line)
    if ok and type(obj) == "table" then
      if obj.type == "session" and obj.name then
        name = obj.name
      elseif obj.type == "message" and obj.message and obj.message.role == "user" then
        local c = obj.message.content
        if type(c) == "string" then
          first_user = c
        elseif type(c) == "table" then
          for _, part in ipairs(c) do
            if type(part) == "table" and part.type == "text" and part.text then
              first_user = part.text
              break
            elseif type(part) == "string" then
              first_user = part
              break
            end
          end
        end
        if first_user then
          break
        end
      end
    end
  end
  f:close()
  if first_user then
    first_user = first_user:gsub("%s+", " "):sub(1, 60)
  end
  return { name = name, preview = first_user }
end

---@return { path: string, label: string, mtime: number }[]
function M.list(cwd)
  local dir = M.session_dir_for(cwd)
  if vim.fn.isdirectory(dir) == 0 then
    return {}
  end
  local files = vim.fn.glob(dir .. "/*.jsonl", false, true)
  local items = {}
  for _, path in ipairs(files) do
    local st = vim.uv.fs_stat(path)
    local mtime = st and st.mtime.sec or 0
    local meta = peek_meta(path) or {}
    local base = vim.fn.fnamemodify(path, ":t")
    local label
    if meta.name and meta.name ~= "" then
      label = meta.name
    elseif meta.preview then
      label = meta.preview
    else
      label = base
    end
    local when = os.date("%Y-%m-%d %H:%M", mtime)
    table.insert(items, {
      path = path,
      mtime = mtime,
      label = string.format("%s  ·  %s", when, label),
    })
  end
  table.sort(items, function(a, b)
    return a.mtime > b.mtime
  end)
  return items
end

--- Newest session for cwd, or nil
---@return { path: string, label: string, mtime: number }|nil
function M.latest(cwd)
  local items = M.list(cwd)
  return items[1]
end

--- Load user/assistant messages from a session jsonl (for chat hydrate)
---@return { role: string, content: any }[]
function M.load_messages(path)
  local out = {}
  if not path or path == "" then
    return out
  end
  local f = io.open(path, "r")
  if not f then
    return out
  end
  for line in f:lines() do
    if line ~= "" then
      local ok, obj = pcall(vim.json.decode, line)
      if ok and type(obj) == "table" and obj.type == "message" and type(obj.message) == "table" then
        local role = obj.message.role
        if role == "user" or role == "assistant" then
          table.insert(out, { role = role, content = obj.message.content })
        end
      end
    end
  end
  f:close()
  return out
end

function M.pick(opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()
  local items = M.list(cwd)
  local dir = M.session_dir_for(cwd)

  -- Pi floats sit above telescope/ui.select — close first or picker looks like "nothing"
  pcall(function()
    require("pi.ui").close()
  end)

  if #items == 0 then
    vim.notify(
      string.format("pi: no sessions for cwd\n%s\nlooked in:\n%s", cwd, dir),
      vim.log.levels.WARN
    )
    return
  end

  vim.notify(string.format("pi: %d session(s) · %s", #items, vim.fn.fnamemodify(cwd, ":~")), vim.log.levels.INFO)

  -- schedule so float close paints before select opens
  vim.schedule(function()
    vim.ui.select(items, {
      prompt = "pi sessions · " .. vim.fn.fnamemodify(cwd, ":~"),
      format_item = function(it)
        return it.label
      end,
    }, function(choice)
      if not choice then
        return
      end
      -- Paint from disk first (don't wait on RPC); then switch agent context
      local msgs = M.load_messages(choice.path)
      require("pi.ui").open()
      require("pi.render").hydrate(require("pi.ui").chat_buf(), msgs, { footer = "· resumed session" })
      vim.notify(string.format("pi: loaded %d message(s)", #msgs), vim.log.levels.INFO)
      require("pi.runtime").switch_session(choice.path, { skip_hydrate = true })
    end)
  end)
end

return M
