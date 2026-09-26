local config = require("pi.config")
local context = require("pi.context")

local M = {}
local buf ---@type integer|nil
local history = {}
local hist_idx = 0 -- 0 = drafting new; 1..#history = browsing

function M.set_buffer(b)
  buf = b
end

function M.buffer()
  return buf
end

function M.history()
  return history
end

function M.clear_history()
  history = {}
  hist_idx = 0
end

function M.setup(b, on_close)
  buf = b
  vim.bo[b].buftype = "nofile"
  vim.bo[b].bufhidden = "hide"
  vim.bo[b].filetype = "markdown"
  local k = config.opts.keys
  local opts = { buffer = b, nowait = true, silent = true }

  local function insert_newline()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    vim.api.nvim_buf_set_text(b, row - 1, col, row - 1, col, { "", "" })
    vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
  end

  -- Clear stale maps from older sessions (pi://input is long-lived)
  for _, lhs in ipairs({ "<CR>", "<S-CR>", "<C-CR>", "<D-CR>", "<M-CR>", "<C-j>", "<NL>" }) do
    pcall(vim.keymap.del, "i", lhs, { buffer = b })
    pcall(vim.keymap.del, "n", lhs, { buffer = b })
  end

  -- Enter submits in normal + insert (Ctrl/Shift+Enter are unreliable in terminals)
  vim.keymap.set({ "n", "i" }, k.submit or "<CR>", function()
    M.submit()
  end, opts)
  -- Extra submit chords for GUI / kitty keyboard-protocol terminals
  for _, lhs in ipairs({ "<C-CR>", "<M-CR>", "<D-CR>" }) do
    vim.keymap.set("i", lhs, function()
      M.submit()
    end, opts)
  end

  -- Portable newline: Ctrl+J (almost all terminals). Also S-CR when distinct.
  local nl = k.newline or "<C-j>"
  vim.keymap.set("i", nl, insert_newline, opts)
  if nl ~= "<C-j>" then
    vim.keymap.set("i", "<C-j>", insert_newline, opts)
  end
  vim.keymap.set("i", "<S-CR>", insert_newline, opts)
  vim.keymap.set("i", "<NL>", insert_newline, opts)

  vim.keymap.set({ "n", "i" }, k.abort, function()
    M.abort()
  end, opts)
  if k.history_prev then
    vim.keymap.set({ "n", "i" }, k.history_prev, function()
      M.history_prev()
    end, opts)
  end
  if k.history_next then
    vim.keymap.set({ "n", "i" }, k.history_next, function()
      M.history_next()
    end, opts)
  end
  if k.steer then
    vim.keymap.set({ "n", "i" }, k.steer, function()
      M.submit({ streamingBehavior = "steer" })
    end, opts)
  end
  local slash_key = k.slash or "/"
  vim.keymap.set("i", slash_key, function()
    local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
    local cur = table.concat(lines, "\n")
    -- empty or only whitespace → open slash picker; else insert /
    if cur:match("^%s*$") then
      require("pi.slash").insert_into(b)
    else
      vim.api.nvim_feedkeys(slash_key, "n", false)
    end
  end, opts)
  if k.mention then
    vim.keymap.set("i", k.mention, function()
      context.pick_file(function(path)
        local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
        local cur = table.concat(lines, "\n")
        vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.split(cur .. " @" .. path .. " ", "\n", { plain = true }))
        vim.cmd("startinsert!")
      end)
    end, opts)
  end
  local skill_key = k.skill or "#"
  vim.keymap.set("i", skill_key, function()
    local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
    local cur = table.concat(lines, "\n")
    if cur:match("^%s*$") then
      require("pi.skills").insert_into(b)
    else
      vim.api.nvim_feedkeys(skill_key, "n", false)
    end
  end, opts)
  if on_close then
    vim.keymap.set("n", "q", on_close, opts)
  end
  -- Leader actions while focused in input (insert mode would otherwise swallow them)
  vim.keymap.set({ "n", "i" }, "<Leader>as", function()
    vim.cmd("stopinsert")
    require("pi.sessions").pick()
  end, vim.tbl_extend("force", opts, { desc = "pi: pick session" }))
  vim.keymap.set({ "n", "i" }, "<Leader>ai", function()
    vim.cmd("stopinsert")
    require("pi").toggle()
  end, vim.tbl_extend("force", opts, { desc = "pi: toggle UI" }))
  vim.keymap.set({ "n", "i" }, "<LocalLeader>as", function()
    vim.cmd("stopinsert")
    require("pi.sessions").pick()
  end, vim.tbl_extend("force", opts, { desc = "pi: pick session" }))
  vim.keymap.set({ "n", "i" }, "<LocalLeader>ai", function()
    vim.cmd("stopinsert")
    require("pi").toggle()
  end, vim.tbl_extend("force", opts, { desc = "pi: toggle UI" }))
end

local function set_draft(text)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text or "", "\n", { plain = true }))
end

function M.history_prev()
  if #history == 0 then
    return
  end
  if hist_idx == 0 then
    hist_idx = #history
  elseif hist_idx > 1 then
    hist_idx = hist_idx - 1
  end
  set_draft(history[hist_idx])
end

function M.history_next()
  if hist_idx == 0 then
    return
  end
  if hist_idx < #history then
    hist_idx = hist_idx + 1
    set_draft(history[hist_idx])
  else
    hist_idx = 0
    set_draft("")
  end
end

---@param opts? { streamingBehavior?: string }
function M.submit(opts)
  opts = opts or {}
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then
    return
  end
  table.insert(history, text)
  hist_idx = 0
  local expanded = context.expand(text)
  local pre = context.preamble()
  local message = pre ~= "" and (pre .. "\n\n" .. expanded) or expanded
  local session = require("pi.session")
  local busy = session.is_busy()
  -- steer/follow-up: tiny suffix in the bubble itself (no role header)
  local display = text
  if busy then
    local mode = opts.streamingBehavior or config.opts.busy_submit or "steer"
    display = text .. (mode == "followUp" and "  ·follow-up" or "  ·steer")
  elseif opts.streamingBehavior == "steer" then
    display = text .. "  ·steer"
  end
  local ui = require("pi.ui")
  local chat = ui.chat_buf()
  if chat then
    local render = require("pi.render")
    render.stick()
    render.append_user(chat, display)
    render.follow(chat, true, ui.chat_win and ui.chat_win() or nil)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  require("pi.runtime").prompt(message, opts)
  pcall(function()
    require("pi.slots").note_goal(text)
  end)
  pcall(function()
    require("pi.statusline").repaint()
  end)
  -- close ask popup after send; stay on chat
  pcall(function()
    require("pi.ui").close_input()
  end)
end

function M.abort()
  require("pi.runtime").abort()
end

return M
