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

local function next_capped_line(f, cap)
  local parts = {}
  local size = 0
  local overflow = false
  while true do
    local block = f:read(8192)
    if not block then
      if overflow or (size == 0 and #parts == 0) then
        return overflow and false or nil
      end
      return table.concat(parts)
    end
    local nl = block:find("\n", 1, true)
    if nl then
      local take = nl - 1
      if take > 0 and block:sub(take, take) == "\r" then
        take = take - 1
      end
      local rest = block:sub(nl + 1)
      if #rest > 0 then
        f:seek("cur", -#rest)
      end
      if overflow or size + take > cap then
        return false
      end
      if take > 0 then
        parts[#parts + 1] = block:sub(1, take)
      end
      return table.concat(parts)
    end
    size = size + #block
    if not overflow and size <= cap then
      parts[#parts + 1] = block
    else
      overflow = true
      parts = {}
    end
  end
end

local function peek_meta(path)
  local name, first_user
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local n = 0
  while n < 40 do
    local line = next_capped_line(f, 4096)
    if line == nil then
      break
    end
    if line ~= false and line ~= "" then
      n = n + 1
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

--- Load recent user/assistant messages. Giant JSONL lines are skipped so a
--- multi‑MB session cannot freeze the editor. Returns messages, truncated.
function M.load_messages(path)
  local out = {}
  local truncated = false
  if not path or path == "" then
    return out, truncated
  end
  local f = io.open(path, "r")
  if not f then
    return out, truncated
  end
  local cap = 80
  while true do
    local line = next_capped_line(f, 16384)
    if line == nil then
      break
    end
    if line == false then
      truncated = true
    elseif line ~= "" then
      local ok, obj = pcall(vim.json.decode, line)
      if ok and type(obj) == "table" and obj.type == "message" and type(obj.message) == "table" then
        local role = obj.message.role
        if role == "user" or role == "assistant" then
          table.insert(out, { role = role, content = obj.message.content })
          if #out > cap then
            table.remove(out, 1)
            truncated = true
          end
        end
      end
    end
  end
  f:close()
  return out, truncated
end

local HISTORY_CHUNK = 65536
local HISTORY_LINE_CAP = 16384
--- Stop a single page before it walks the whole file. The next scroll continues.
local HISTORY_SCAN_BUDGET = 1024 * 1024

local function decode_message_line(line)
  if type(line) ~= "string" or line == "" or #line > HISTORY_LINE_CAP then
    return nil
  end
  if not line:find('^{%s*"type"%s*:%s*"message"', 1) then
    return nil
  end
  local ok, obj = pcall(vim.json.decode, line)
  if not ok or type(obj) ~= "table" or obj.type ~= "message" or type(obj.message) ~= "table" then
    return nil
  end
  local role = obj.message.role
  if role ~= "user" and role ~= "assistant" then
    return nil
  end
  return { role = role, content = obj.message.content }
end

--- Tail cursor only. Does not read the file.
function M.open_history(path)
  local size = 0
  if path and path ~= "" then
    local f = io.open(path, "rb")
    if f then
      size = f:seek("end") or 0
      f:close()
    end
  end
  return { path = path, cursor = size }
end

--- Read the next older page from the end of the file. Returns messages
--- (oldest→newest) and whether nothing earlier remains.
--- `state.cursor` is the byte offset where the next older page should stop.
function M.history_page(state, n)
  n = n or 6
  if not state or not state.path or (state.cursor or 0) <= 0 then
    return {}, true
  end
  local f = io.open(state.path, "rb")
  if not f then
    state.cursor = 0
    return {}, true
  end
  local found = {}
  local partial = ""
  local pos = state.cursor
  local scanned = 0
  local filled = false
  while #found < n and pos > 0 and scanned < HISTORY_SCAN_BUDGET do
    local start = math.max(0, pos - HISTORY_CHUNK)
    f:seek("set", start)
    local data = f:read(pos - start) or ""
    scanned = scanned + #data
    if partial ~= "" then
      if #data + #partial > HISTORY_LINE_CAP then
        partial = ""
      else
        data = data .. partial
        partial = ""
      end
    end
    local blob_off = start
    local skip = false
    if start > 0 then
      local nl = data:find("\n", 1, true)
      if not nl then
        if #data <= HISTORY_LINE_CAP then
          partial = data
        end
        pos = start
        skip = true
      else
        if nl - 1 <= HISTORY_LINE_CAP then
          partial = data:sub(1, nl - 1)
          if partial:sub(-1) == "\r" then
            partial = partial:sub(1, -2)
          end
        end
        blob_off = start + nl
        data = data:sub(nl + 1)
      end
    end
    if not skip then
      local lines = {}
      local i = 1
      local off = blob_off
      while i <= #data do
        local nl = data:find("\n", i, true)
        local text, next_i, next_off
        if not nl then
          text = data:sub(i)
          next_i = #data + 1
          next_off = blob_off + #data
        else
          text = data:sub(i, nl - 1)
          next_i = nl + 1
          next_off = blob_off + nl
        end
        if text:sub(-1) == "\r" then
          text = text:sub(1, -2)
        end
        if text ~= "" then
          lines[#lines + 1] = { off = off, text = text }
        end
        i = next_i
        off = next_off
      end
      for li = #lines, 1, -1 do
        local msg = decode_message_line(lines[li].text)
        if msg then
          found[#found + 1] = { off = lines[li].off, msg = msg }
          if #found >= n then
            state.cursor = lines[li].off
            filled = true
            break
          end
        end
      end
      if not filled then
        pos = start
      end
    end
  end
  f:close()
  if not filled then
    if pos <= 0 and partial ~= "" and #found < n then
      local msg = decode_message_line(partial)
      if msg then
        found[#found + 1] = { off = 0, msg = msg }
      end
    end
    state.cursor = pos > 0 and pos or 0
  end
  local msgs = {}
  for i = #found, 1, -1 do
    msgs[#msgs + 1] = found[i].msg
  end
  return msgs, state.cursor <= 0
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
      local hist = M.open_history(choice.path)
      local msgs, exhausted = M.history_page(hist)
      require("pi.ui").open()
      local footer = exhausted and "· resumed session" or "· 往上滚查看更早"
      require("pi.render").hydrate(require("pi.ui").chat_buf(), msgs, {
        footer = footer,
        history = exhausted and nil or hist,
      })
      vim.notify(string.format("pi: loaded %d message(s)", #msgs), vim.log.levels.INFO)
      require("pi.runtime").switch_session(choice.path, { skip_hydrate = true })
      require("pi.ui").focus_chat()
      pcall(vim.cmd, "stopinsert")
    end)
  end)
end

return M
