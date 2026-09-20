-- Chat buffer rendering: compact tool lines, collapse repeats, stream assistant text
local M = {}

-- pending tools by toolCallId → { name, detail, line }
local pending = {}
-- last compact tool summary for collapse: { name, detail, count, line_idx }
local last_tool = nil
local streaming_assistant = false
local streaming_thinking = false
local follow_scheduled = false
--- Cleared only by gg; content updates always force-follow while true
local stick_bottom = true
--- Ignore WinScrolled until this hrtime
local suppress_until = 0
local scroll_autocmd ---@type integer|nil

function M.setup(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
end

--- Temporarily unlock chat buf for programmatic writes
local function with_write(buf, fn)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local mod = vim.bo[buf].modifiable
  local ro = vim.bo[buf].readonly
  vim.bo[buf].readonly = false
  vim.bo[buf].modifiable = true
  local ok, err = pcall(fn)
  vim.bo[buf].modifiable = mod
  vim.bo[buf].readonly = ro
  -- always re-lock after write
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  if not ok then
    error(err)
  end
end

function M.reset(buf)
  pending = {}
  last_tool = nil
  streaming_assistant = false
  streaming_thinking = false
  follow_scheduled = false
  stick_bottom = true
  suppress_until = 0
  with_write(buf, function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# pi chat", "" })
  end)
end

function M.stick()
  stick_bottom = true
end

function M.unstick()
  stick_bottom = false
end

--- Scroll chat window to latest content.
--- @param buf integer
--- @param force? boolean
--- @param win? integer explicit chat win (preferred over win_findbuf)
function M.follow(buf, force, win)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if not force and not stick_bottom then
    return
  end
  local last = vim.api.nvim_buf_line_count(buf)
  if last < 1 then
    return
  end
  local target = last
  local probe = vim.api.nvim_buf_get_lines(buf, math.max(0, last - 40), last, false)
  for i = #probe, 1, -1 do
    if probe[i] ~= "" then
      target = last - (#probe - i)
      break
    end
  end

  local wins_list = {}
  if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
    wins_list = { win }
  else
    local ok_ui, ui = pcall(require, "pi.ui")
    if ok_ui and ui.chat_win then
      local w = ui.chat_win()
      if w and vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_buf(w) == buf then
        wins_list = { w }
      end
    end
    if #wins_list == 0 then
      wins_list = vim.fn.win_findbuf(buf) or {}
    end
  end
  if #wins_list == 0 then
    return
  end

  suppress_until = vim.uv.hrtime() + 200e6
  for _, w in ipairs(wins_list) do
    if vim.api.nvim_win_is_valid(w) then
      local height = math.max(1, vim.api.nvim_win_get_height(w))
      local topline = math.max(1, target - height + 1)
      pcall(function()
        vim.wo[w].scrolloff = 0
      end)
      -- Do NOT steal focus from input — only mutate the chat win view
      pcall(vim.api.nvim_win_set_cursor, w, { target, 0 })
      pcall(vim.api.nvim_win_call, w, function()
        vim.fn.winrestview({
          lnum = target,
          col = 0,
          topline = topline,
          leftcol = 0,
          curswant = 0,
        })
      end)
      -- Force GUI/TUI to paint the non-current float
      pcall(vim.api.nvim__redraw, { win = w, cursor = true, valid = true, flush = true })
    end
  end
end

local follow_timer ---@type uv.uv_timer_t|nil

local function schedule_follow(buf)
  -- coalesce rapid stream deltas into one scroll ~per frame
  if follow_timer and not follow_timer:is_closing() then
    follow_timer:stop()
    follow_timer:close()
    follow_timer = nil
  end
  follow_scheduled = true
  follow_timer = vim.uv.new_timer()
  follow_timer:start(30, 0, vim.schedule_wrap(function()
    if follow_timer and not follow_timer:is_closing() then
      follow_timer:stop()
      follow_timer:close()
    end
    follow_timer = nil
    follow_scheduled = false
    local win
    pcall(function()
      win = require("pi.ui").chat_win()
    end)
    M.follow(buf, true, win)
  end))
end

--- User scroll tracking + G/gg helpers
function M.attach_scroll(win, buf)
  if scroll_autocmd then
    pcall(vim.api.nvim_del_autocmd, scroll_autocmd)
    scroll_autocmd = nil
  end
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  pcall(function()
    vim.wo[win].scrolloff = 0
  end)

  scroll_autocmd = vim.api.nvim_create_autocmd("WinScrolled", {
    callback = function(ev)
      if vim.uv.hrtime() < suppress_until then
        return
      end
      if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
        return
      end
      local match = tostring(ev.match or "")
      if match ~= "" and not match:find(tostring(win), 1, true) then
        return
      end
      -- Only unstick when user is focused in chat and scrolls away
      if vim.api.nvim_get_current_win() ~= win then
        return
      end
      local last = vim.api.nvim_buf_line_count(buf)
      local height = math.max(1, vim.api.nvim_win_get_height(win))
      local ok, view = pcall(vim.api.nvim_win_call, win, function()
        return vim.fn.winsaveview()
      end)
      if not ok or type(view) ~= "table" then
        return
      end
      local bottom_visible = (view.topline or 1) + height - 1
      if bottom_visible < last - 1 then
        stick_bottom = false
      else
        stick_bottom = true
      end
    end,
  })

  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "G", function()
    stick_bottom = true
    M.follow(buf, true)
  end, opts)
  vim.keymap.set("n", "gg", function()
    stick_bottom = false
    suppress_until = vim.uv.hrtime() + 100e6
    vim.cmd("normal! gg")
  end, opts)
  -- keep chat view read-only: leave insert immediately
  vim.keymap.set("n", "i", "<Nop>", opts)
  vim.keymap.set("n", "a", "<Nop>", opts)
  vim.keymap.set("n", "o", "<Nop>", opts)
  vim.keymap.set("n", "O", "<Nop>", opts)
  vim.keymap.set("n", "c", "<Nop>", opts)
  vim.keymap.set("n", "d", "<Nop>", opts)
  vim.keymap.set("n", "x", "<Nop>", opts)
  vim.keymap.set("n", "r", "<Nop>", opts)
  vim.keymap.set("n", "R", "<Nop>", opts)
  vim.keymap.set("n", "p", "<Nop>", opts)
  vim.keymap.set("n", "P", "<Nop>", opts)
end

function M.append(buf, line)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  line = line == nil and "" or tostring(line)
  -- nvim_buf_set_lines forbids "\n" inside a single item
  local lines
  if line:find("\n", 1, true) then
    lines = vim.split(line, "\n", { plain = true })
  else
    lines = { line }
  end
  with_write(buf, function()
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
  end)
  last_tool = nil
  schedule_follow(buf)
end

local function line_count(buf)
  return vim.api.nvim_buf_line_count(buf)
end

local function set_line(buf, idx, text)
  with_write(buf, function()
    vim.api.nvim_buf_set_lines(buf, idx - 1, idx, false, { text })
  end)
end

local function tool_detail(ev)
  local args = ev.args or ev.input or ev.toolArguments or {}
  if type(args) ~= "table" then
    return ""
  end
  local path = args.path or args.file or args.filename
  if path then
    return vim.fn.fnamemodify(tostring(path), ":.")
  end
  if args.command then
    return tostring(args.command):gsub("%s+", " "):sub(1, 60)
  end
  if args.old_text then
    return "replace"
  end
  return ""
end

local function short_name(name)
  name = tostring(name or "?")
  return name:gsub("^nvim_", "")
end

local function format_tool(name, detail, ok, count)
  local mark = ok == nil and "…" or (ok and "✓" or "✗")
  local base = string.format("⚙ %s", short_name(name))
  if detail and detail ~= "" then
    base = base .. " `" .. detail .. "`"
  end
  base = base .. " " .. mark
  if count and count > 1 then
    base = base .. string.format(" ×%d", count)
  end
  return base
end

local function upsert_tool_end(buf, name, detail, ok)
  local key_name = short_name(name)
  local key_detail = detail or ""
  if
    ok
    and last_tool
    and last_tool.name == key_name
    and last_tool.detail == key_detail
    and last_tool.ok
    and last_tool.line
    and last_tool.line <= line_count(buf)
  then
    last_tool.count = last_tool.count + 1
    set_line(buf, last_tool.line, format_tool(name, detail, true, last_tool.count))
    schedule_follow(buf)
    return
  end
  M.append(buf, format_tool(name, detail, ok, 1))
  last_tool = {
    name = key_name,
    detail = key_detail,
    ok = ok,
    count = 1,
    line = line_count(buf),
  }
end

function M.jump_message(buf, win, dir)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  win = win or 0
  local cur = vim.api.nvim_win_get_cursor(win)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local function is_header(s)
    return s:match("^### ") or s:match("^— agent") or s:match("^# pi chat")
  end
  if dir > 0 then
    for i = cur + 1, #lines do
      if is_header(lines[i]) then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        return
      end
    end
  else
    for i = cur - 1, 1, -1 do
      if is_header(lines[i]) then
        vim.api.nvim_win_set_cursor(win, { i, 0 })
        return
      end
    end
  end
end

local function ensure_assistant_header(buf)
  if streaming_thinking then
    streaming_thinking = false
  end
  if streaming_assistant then
    return
  end
  streaming_assistant = true
  last_tool = nil
  with_write(buf, function()
    -- no trailing blank: empty line + leading \n in deltas caused a sparse "empty bottom"
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "### assistant" })
  end)
  schedule_follow(buf)
end

local function ensure_thinking_header(buf)
  if streaming_thinking then
    return
  end
  streaming_thinking = true
  -- text after thinking needs a fresh ### assistant
  streaming_assistant = false
  last_tool = nil
  with_write(buf, function()
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "### thinking" })
  end)
  schedule_follow(buf)
end

local function is_structural_line(s)
  return s:match("^—") or s:match("^⚙") or s:match("^###") or s:match("^# pi")
end

local function append_text_delta(buf, delta)
  delta = tostring(delta):gsub("\r\n", "\n"):gsub("\r", "\n")
  local parts = vim.split(delta, "\n", { plain = true })
  with_write(buf, function()
    local n = line_count(buf)
    local last = vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1] or ""

    local function push_line(text)
      n = line_count(buf)
      last = vim.api.nvim_buf_get_lines(buf, n - 1, n, false)[1] or ""
      -- collapse consecutive blank lines (keep at most one)
      if text == "" and last == "" then
        return
      end
      -- thinking block: markdown blockquote so it reads as secondary
      if streaming_thinking and text ~= "" and not text:match("^>") then
        text = "> " .. text
      elseif streaming_thinking and text == "" then
        text = ">"
      end
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { text })
    end

    if is_structural_line(last) then
      push_line(parts[1])
    else
      local chunk = parts[1]
      -- continuing a thinking line already prefixed with "> "
      vim.api.nvim_buf_set_lines(buf, n - 1, n, false, { last .. chunk })
    end

    for i = 2, #parts do
      push_line(parts[i])
    end
  end)
  last_tool = nil
  schedule_follow(buf)
end

function M.on_event(buf, ev)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  if ev.type == "tool_execution_start" then
    local id = ev.toolCallId or ev.id or tostring(vim.uv.hrtime())
    local detail = tool_detail(ev)
    pending[id] = { name = ev.toolName, detail = detail }
    return
  end

  if ev.type == "tool_execution_end" then
    local id = ev.toolCallId or ev.id
    local meta = (id and pending[id]) or { name = ev.toolName, detail = "" }
    if id then
      pending[id] = nil
    end
    upsert_tool_end(buf, meta.name or ev.toolName, meta.detail, not ev.isError)
    return
  end

  if ev.type == "agent_start" then
    streaming_assistant = false
    streaming_thinking = false
    pending = {}
    stick_bottom = true
    M.append(buf, "— agent —")
    return
  end

  if ev.type == "agent_end" then
    streaming_assistant = false
    streaming_thinking = false
    last_tool = nil
    -- Surface API / model failures (e.g. 401) that produced no text_delta
    local msgs = ev.messages
    if type(msgs) == "table" then
      for i = #msgs, 1, -1 do
        local raw = msgs[i]
        local m = type(raw) == "table" and (raw.message or raw) or nil
        if type(m) == "table" and m.role == "assistant" then
          if m.stopReason == "error" or (m.errorMessage and m.errorMessage ~= "") then
            local err = m.errorMessage or "assistant stopped with error"
            M.append(buf, "### error")
            for line in (tostring(err) .. "\n"):gmatch("(.-)\n") do
              M.append(buf, line)
            end
            vim.schedule(function()
              vim.notify("pi: " .. tostring(err):sub(1, 200), vim.log.levels.ERROR)
            end)
          end
          break
        end
      end
    end
    schedule_follow(buf)
    return
  end

  if ev.type == "message_update" and ev.assistantMessageEvent then
    local a = ev.assistantMessageEvent
    local show_think = require("pi.config").opts.show_thinking ~= false
    if a.type == "text_delta" and a.delta then
      ensure_assistant_header(buf)
      append_text_delta(buf, a.delta)
    elseif show_think and (a.type == "thinking_delta" or a.type == "thinking_start") then
      if a.type == "thinking_start" or (a.delta and a.delta ~= "") then
        ensure_thinking_header(buf)
      end
      if a.delta and a.delta ~= "" then
        append_text_delta(buf, a.delta)
      end
    elseif a.type == "thinking_end" then
      streaming_thinking = false
      schedule_follow(buf)
    elseif a.type == "error" then
      local err = a.errorMessage or a.message or a.error or "assistant error"
      M.append(buf, "### error")
      for line in (tostring(err) .. "\n"):gmatch("(.-)\n") do
        M.append(buf, line)
      end
      streaming_assistant = false
      streaming_thinking = false
      vim.schedule(function()
        vim.notify("pi: " .. tostring(err):sub(1, 200), vim.log.levels.ERROR)
      end)
    elseif a.type == "text_end" or a.type == "done" then
      streaming_assistant = false
      streaming_thinking = false
      schedule_follow(buf)
    end
  end
end

function M._pending_count()
  local n = 0
  for _ in pairs(pending) do
    n = n + 1
  end
  return n
end

function M._last_tool()
  return last_tool
end

--- Extract display text from a message content field
function M.message_text(content)
  if type(content) == "string" then
    return content
  end
  if type(content) ~= "table" then
    return ""
  end
  local texts = {}
  local thinking = {}
  local tools = 0
  local show_think = require("pi.config").opts.show_thinking ~= false
  for _, part in ipairs(content) do
    if type(part) == "string" then
      table.insert(texts, part)
    elseif type(part) == "table" then
      if part.type == "text" and part.text and part.text ~= "" then
        table.insert(texts, part.text)
      elseif show_think and part.type == "thinking" and part.thinking and part.thinking ~= "" then
        table.insert(thinking, part.thinking)
      elseif part.type == "toolCall" then
        tools = tools + 1
      end
    end
  end
  local chunks = {}
  if #thinking > 0 then
    local body = table.concat(thinking, "\n")
    local quoted = {}
    for line in (body .. "\n"):gmatch("(.-)\n") do
      table.insert(quoted, line == "" and ">" or ("> " .. line))
    end
    table.insert(chunks, "### thinking\n" .. table.concat(quoted, "\n"))
  end
  if #texts > 0 then
    local body = table.concat(texts, "\n")
    if #thinking > 0 then
      table.insert(chunks, "### assistant\n" .. body)
    else
      table.insert(chunks, body)
    end
  end
  local out = table.concat(chunks, "\n\n")
  if tools > 0 then
    local line = string.format("⚙ %d tool call(s)", tools)
    out = out ~= "" and (out .. "\n" .. line) or line
  end
  return out
end

--- Normalize get_messages payload → list of {role, content}
function M.normalize_messages(data)
  if type(data) ~= "table" then
    return {}
  end
  local list = data.messages or data
  if type(list) ~= "table" then
    return {}
  end
  -- single message object?
  if list.role or list.message then
    list = { list }
  end
  local out = {}
  for _, msg in ipairs(list) do
    if type(msg) == "table" then
      local role = msg.role
      local content = msg.content
      if msg.message and type(msg.message) == "table" then
        role = role or msg.message.role
        content = content or msg.message.content
      end
      if role == "user" or role == "assistant" then
        table.insert(out, { role = role, content = content })
      end
    end
  end
  return out
end

--- Rebuild chat buffer from historical messages (skip toolResult spam)
function M.hydrate(buf, messages, opts)
  opts = opts or {}
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return 0
  end
  M.reset(buf)
  local count = 0
  for _, msg in ipairs(messages or {}) do
    local text = M.message_text(msg.content)
    if text and text:match("%S") then
      if msg.role == "user" then
        M.append(buf, "### you")
      elseif not text:match("^### thinking") and not text:match("^### assistant") then
        M.append(buf, "### assistant")
      end
      for line in (text .. "\n"):gmatch("(.-)\n") do
        -- collapse extreme blank runs
        M.append(buf, line)
      end
      M.append(buf, "")
      count = count + 1
    end
  end
  if opts.footer ~= false then
    M.append(buf, opts.footer or "· resumed session")
  end
  stick_bottom = true
  schedule_follow(buf)
  return count
end

return M
