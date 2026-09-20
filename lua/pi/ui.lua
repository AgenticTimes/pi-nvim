local config = require("pi.config")

local M = {}
local wins = { chat = nil, input = nil }
local bufs = { chat = nil, input = nil }
local fullscreen = true -- default: edge-to-edge chat
local editor_win ---@type integer|nil

local function remember_editor()
  local cur = vim.api.nvim_get_current_win()
  if cur == wins.chat or cur == wins.input then
    return
  end
  local cfg = vim.api.nvim_win_get_config(cur)
  if cfg.relative and cfg.relative ~= "" then
    return
  end
  editor_win = cur
end

--- Chat always fills the editor (ignore side-panel mode)
local function chat_geometry()
  local cmd = math.max(1, vim.o.cmdheight or 1)
  return {
    width = vim.o.columns,
    height = math.max(8, vim.o.lines - cmd),
    row = 0,
    col = 0,
    border = "none",
  }
end

--- Centered search-style input popup
local function input_geometry()
  local w = math.min(vim.o.columns - 4, math.max(48, math.floor(vim.o.columns * 0.72)))
  local h = math.max(3, math.min(10, math.floor(vim.o.lines * 0.18)))
  return {
    width = w,
    height = h,
    row = math.max(1, math.floor((vim.o.lines - h) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - w) / 2)),
    border = "rounded",
  }
end

local function configure_chat_win(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].showbreak = "↪ "
  vim.wo[win].signcolumn = "yes:1"
  -- Opaque: global NormalFloat is often transparent (theme), which shows the editor through
  pcall(function()
    vim.wo[win].winhl = "Normal:PiChatNormal,NormalFloat:PiChatNormal,FloatBorder:PiChatBorder"
  end)
  pcall(function()
    vim.wo[win].smoothscroll = true
  end)
end

local function configure_ask_win(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  pcall(function()
    vim.wo[win].winhl = "Normal:PiAskNormal,NormalFloat:PiAskNormal,FloatBorder:PiAskBorder"
  end)
end

local function adj_bg(c, delta)
  if type(c) ~= "number" then
    return nil
  end
  local r = math.floor(c / 65536) % 256
  local g = math.floor(c / 256) % 256
  local b = c % 256
  local function clamp(x)
    return math.max(0, math.min(255, x + delta))
  end
  return clamp(r) * 65536 + clamp(g) * 256 + clamp(b)
end

local function muted_fg(fg)
  -- Secondary text: ~70% of Normal fg, floored so it stays readable on dark themes
  if type(fg) ~= "number" then
    return 0xa9b1d6
  end
  local r = math.floor(fg / 65536) % 256
  local g = math.floor(fg / 256) % 256
  local b = fg % 256
  local function tone(c)
    return math.max(0x88, math.min(255, math.floor(c * 0.72 + 0x28)))
  end
  return tone(r) * 65536 + tone(g) * 256 + tone(b)
end

local hl_autocmd ---@type integer|nil
local function ensure_hl()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local bg = normal.bg or 0x1e1e1e
  local fg = normal.fg or 0xffffff
  local ask_bg = adj_bg(bg, 12) or bg
  local think_fg = muted_fg(fg)
  local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
  if type(comment.fg) == "number" then
    -- prefer Comment if it is already brighter than our floor
    local cr = math.floor(comment.fg / 65536) % 256
    local cg = math.floor(comment.fg / 256) % 256
    local cb = comment.fg % 256
    if (cr + cg + cb) / 3 >= 0x88 then
      think_fg = comment.fg
    end
  end
  vim.api.nvim_set_hl(0, "PiChatNormal", { bg = bg, fg = fg })
  vim.api.nvim_set_hl(0, "PiChatBorder", { bg = bg, fg = muted_fg(fg) })
  vim.api.nvim_set_hl(0, "PiAskNormal", { bg = ask_bg, fg = fg })
  vim.api.nvim_set_hl(0, "PiAskBorder", { bg = ask_bg, fg = 0x7aa2f7, bold = true })
  local bubble_bg = adj_bg(bg, 18) or bg
  vim.api.nvim_set_hl(0, "PiYou", { fg = 0x7aa2f7, bold = true, bg = bg })
  vim.api.nvim_set_hl(0, "PiYouBar", { fg = 0x7aa2f7, bg = bg })
  vim.api.nvim_set_hl(0, "PiYouBubble", { bg = bubble_bg, fg = fg })
  vim.api.nvim_set_hl(0, "PiYouBorder", { fg = 0x7aa2f7, bg = bubble_bg })
  -- tool calls: violet, squarer box than user turns
  local tool_bg = adj_bg(bg, 12) or bg
  vim.api.nvim_set_hl(0, "PiToolBar", { fg = 0xbb9af7, bg = bg })
  vim.api.nvim_set_hl(0, "PiToolBubble", { bg = tool_bg })
  vim.api.nvim_set_hl(0, "PiToolBorder", { fg = 0xbb9af7, bg = tool_bg })
  -- thinking: muted, dashed box, bg only so the PiThinking italic text hl wins
  local think_bg = adj_bg(bg, 5) or bg
  vim.api.nvim_set_hl(0, "PiThinkBar", { fg = think_fg, bg = bg })
  vim.api.nvim_set_hl(0, "PiThinkBubble", { bg = think_bg })
  vim.api.nvim_set_hl(0, "PiThinkBorder", { fg = think_fg, bg = think_bg })
  vim.api.nvim_set_hl(0, "PiAssistant", { fg = 0x9ece6a, bold = true, bg = bg })
  vim.api.nvim_set_hl(0, "PiThinking", { fg = think_fg, italic = true, bg = bg })
  vim.api.nvim_set_hl(0, "PiAgent", { fg = 0xbb9af7, bold = true, bg = bg })
  vim.api.nvim_set_hl(0, "PiError", { fg = 0xf7768e, bold = true, bg = bg })
  if not hl_autocmd then
    hl_autocmd = vim.api.nvim_create_autocmd("ColorScheme", {
      callback = function()
        ensure_hl()
      end,
    })
  end
end

function M.chat_buf()
  if bufs.chat and vim.api.nvim_buf_is_valid(bufs.chat) then
    return bufs.chat
  end
  local render = require("pi.render")
  local b = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, b, "pi://chat")
  render.setup(b)
  render.reset(b)
  bufs.chat = b
  return b
end

function M.input_buf()
  if bufs.input and vim.api.nvim_buf_is_valid(bufs.input) then
    -- re-bind keys each open so Enter/Shift no longer submit after config updates
    require("pi.input").setup(bufs.input, function()
      M.close_input()
    end)
    return bufs.input
  end
  local input = require("pi.input")
  local b = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, b, "pi://input")
  input.setup(b, function()
    M.close_input()
  end)
  bufs.input = b
  return b
end

function M.is_open()
  return wins.chat ~= nil and vim.api.nvim_win_is_valid(wins.chat)
end

function M.is_input_open()
  return wins.input ~= nil and vim.api.nvim_win_is_valid(wins.input)
end

--- Absolute path of the editor buffer remembered before pi floats opened
function M.editor_path()
  if editor_win and vim.api.nvim_win_is_valid(editor_win) then
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor_win))
    if name ~= "" and not name:match("^pi://") then
      return vim.fn.fnamemodify(name, ":p")
    end
  end
  return nil
end

--- Drop/raise ask float so pickers (telescope zindex≈100) can sit above
function M.set_input_zindex(z)
  if not M.is_input_open() then
    return
  end
  local cfg = vim.api.nvim_win_get_config(wins.input)
  cfg.zindex = z
  pcall(vim.api.nvim_win_set_config, wins.input, cfg)
end

local PICKER_BEHIND_Z = 40
local ASK_DEFAULT_Z = 60

--- Focus existing ask win only (no open_input / inject_yank)
local function refocus_input_win()
  if not M.is_input_open() then
    return
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
    if name:match("pi://input") then
      vim.api.nvim_set_current_win(w)
      return
    end
  end
end

--- Run a picker while ask (if open) sits behind it.
--- `open_fn(done)` must call `done()` when the picker closes (select or cancel).
---@param open_fn fun(done: fun())
function M.with_picker(open_fn)
  local had_input = M.is_input_open()
  if had_input then
    M.set_input_zindex(PICKER_BEHIND_Z)
  end
  local finished = false
  local function done()
    if finished then
      return
    end
    finished = true
    if had_input then
      M.set_input_zindex(ASK_DEFAULT_Z)
      refocus_input_win()
    end
  end
  vim.schedule(function()
    open_fn(done)
  end)
end

function M.is_fullscreen()
  return fullscreen
end

local function apply_chat_layout()
  if not M.is_open() then
    return
  end
  local g = chat_geometry()
  local title = ""
  if g.border ~= "none" then
    title = " pi chat "
    pcall(function()
      local bits = require("pi.session").title_bits()
      if bits ~= "" then
        title = " pi · " .. bits .. " "
      end
    end)
  end
  pcall(vim.api.nvim_win_set_config, wins.chat, {
    relative = "editor",
    width = g.width,
    height = g.height,
    row = g.row,
    col = g.col,
    style = "minimal",
    border = g.border,
    title = title,
    title_pos = "center",
  })
  configure_chat_win(wins.chat)
end

local function apply_input_layout()
  if not M.is_input_open() then
    return
  end
  local g = input_geometry()
  local cur = vim.api.nvim_win_get_config(wins.input)
  pcall(vim.api.nvim_win_set_config, wins.input, {
    relative = "editor",
    width = g.width,
    height = g.height,
    row = g.row,
    col = g.col,
    style = "minimal",
    border = g.border,
    title = " pi · ask ",
    title_pos = "center",
    zindex = cur.zindex or 60,
  })
  configure_ask_win(wins.input)
end

function M.close_input()
  if wins.input and vim.api.nvim_win_is_valid(wins.input) then
    pcall(vim.api.nvim_win_close, wins.input, true)
  end
  wins.input = nil
  -- drop stale draft (e.g. leftover CLIPBOARD_YANK) so next open starts clean
  if bufs.input and vim.api.nvim_buf_is_valid(bufs.input) then
    pcall(vim.api.nvim_buf_set_lines, bufs.input, 0, -1, false, { "" })
  end
  -- Ask is always insert; without stopinsert, insert sticks to chat after submit.
  pcall(vim.cmd, "stopinsert")
  if M.is_open() then
    vim.api.nvim_set_current_win(wins.chat)
  end
end

--- Only inject yanks from this Neovim session (TextYankPost), never raw `+`
--- clipboard — that picks up OS junk / test sentinels like CLIPBOARD_YANK.
local pending_yank ---@type string|nil

local yank_autocmd ---@type integer|nil
local function ensure_yank_watch()
  if yank_autocmd then
    return
  end
  yank_autocmd = vim.api.nvim_create_autocmd("TextYankPost", {
    callback = function()
      local ev = vim.v.event
      if type(ev) ~= "table" or type(ev.regcontents) ~= "table" then
        return
      end
      local text = table.concat(ev.regcontents, "\n")
      if text:match("%S") then
        pending_yank = text:gsub("\n$", "")
      end
    end,
  })
end

--- Prefill ask buffer with last in-session yank (`,y` / `vy`); consume once
local function inject_yank()
  ensure_yank_watch()
  local b = M.input_buf()
  if not b or not vim.api.nvim_buf_is_valid(b) then
    return false
  end
  local yank = pending_yank
  pending_yank = nil
  if not yank or not yank:match("%S") then
    -- clear stale draft / leftover CLIPBOARD_YANK so empty open stays empty
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { "" })
    return false
  end
  vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.split(yank, "\n", { plain = true }))
  return true
end

--- Test helper: queue a yank without touching the OS clipboard
function M._set_pending_yank_for_test(text)
  pending_yank = text
end

--- Open centered input popup (search-style)
---@param opts? { no_yank?: boolean }
function M.open_input(opts)
  opts = opts or {}
  if not M.is_open() then
    M.open()
  end
  ensure_hl()
  ensure_yank_watch()
  -- ensure keymaps rebound (long-lived pi://input keeps old <CR>=submit otherwise)
  M.input_buf()
  -- inject at most once (pending yank is consumed); empty → wipe stale draft
  if not opts.no_yank then
    inject_yank()
  end
  if M.is_input_open() then
    configure_ask_win(wins.input)
    vim.api.nvim_set_current_win(wins.input)
    vim.cmd("startinsert!")
    return
  end
  local g = input_geometry()
  wins.input = vim.api.nvim_open_win(M.input_buf(), true, {
    relative = "editor",
    width = g.width,
    height = g.height,
    row = g.row,
    col = g.col,
    style = "minimal",
    border = g.border,
    title = " pi · ask ",
    title_pos = "center",
    zindex = 60,
  })
  configure_ask_win(wins.input)
  vim.cmd("startinsert!")
end

function M.open()
  remember_editor()
  if M.is_open() then
    vim.api.nvim_set_current_win(wins.chat)
    return
  end
  ensure_hl()
  require("pi.runtime").ensure_started()
  local g = chat_geometry()
  local title = ""
  if g.border ~= "none" then
    title = " pi chat "
    pcall(function()
      local bits = require("pi.session").title_bits()
      if bits ~= "" then
        title = " pi · " .. bits .. " "
      end
    end)
  end
  wins.chat = vim.api.nvim_open_win(M.chat_buf(), true, {
    relative = "editor",
    width = g.width,
    height = g.height,
    row = g.row,
    col = g.col,
    style = "minimal",
    border = g.border,
    title = title,
    title_pos = "center",
  })
  configure_chat_win(wins.chat)
  require("pi.render").attach_scroll(wins.chat, M.chat_buf())
  require("pi.render").stick()
  require("pi.render").follow(M.chat_buf(), true)
  -- no auto-insert: user presses Enter to open ask popup
end

function M.close()
  M.close_input()
  if wins.chat and vim.api.nvim_win_is_valid(wins.chat) then
    pcall(vim.api.nvim_win_close, wins.chat, true)
  end
  wins = { chat = nil, input = nil }
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

function M.toggle_fullscreen()
  fullscreen = not fullscreen
  if M.is_open() then
    apply_chat_layout()
    apply_input_layout()
  else
    M.open()
  end
end

function M.focus_chat()
  M.close_input()
  if wins.chat and vim.api.nvim_win_is_valid(wins.chat) then
    vim.api.nvim_set_current_win(wins.chat)
  end
end

function M.focus_input()
  M.open_input()
end

function M.focus_editor()
  M.close_input()
  if editor_win and vim.api.nvim_win_is_valid(editor_win) then
    vim.api.nvim_set_current_win(editor_win)
    return true
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if w ~= wins.chat and w ~= wins.input then
      local cfg = vim.api.nvim_win_get_config(w)
      if not cfg.relative or cfg.relative == "" then
        vim.api.nvim_set_current_win(w)
        return true
      end
    end
  end
  return false
end

function M.focus_toggle()
  local cur = vim.api.nvim_get_current_win()
  if cur == wins.chat or cur == wins.input then
    M.focus_editor()
  else
    remember_editor()
    if M.is_open() then
      M.focus_chat()
    else
      M.open()
    end
  end
end

function M.cycle_focus()
  if not M.is_open() then
    return
  end
  if M.is_input_open() then
    M.focus_chat()
  else
    M.open_input()
  end
end

function M.refresh_title()
  apply_chat_layout()
end

function M.chat_win()
  return wins.chat
end

function M.input_win()
  return wins.input
end

function M.on_event(ev)
  local buf = M.chat_buf()
  require("pi.render").on_event(buf, ev)
  if wins.chat and vim.api.nvim_win_is_valid(wins.chat) then
    require("pi.render").follow(buf, true, wins.chat)
  end
end

local function map_ui_keys()
  local k = config.opts.keys
  local chat = M.chat_buf()
  local input = M.input_buf()
  local opts_c = { buffer = chat, nowait = true, silent = true }
  local opts_i = { buffer = input, nowait = true, silent = true }

  -- Enter on chat → open ask popup
  vim.keymap.set("n", "<CR>", function()
    M.open_input()
  end, vim.tbl_extend("force", opts_c, { desc = "pi: open ask" }))

  local tab = k.focus_cycle or "<Tab>"
  vim.keymap.set("n", tab, function()
    M.cycle_focus()
  end, opts_c)
  vim.keymap.set({ "n", "i" }, tab, function()
    M.cycle_focus()
  end, opts_i)

  -- Esc closes ask popup (search-style)
  vim.keymap.set({ "n", "i" }, "<Esc>", function()
    vim.cmd("stopinsert")
    M.close_input()
  end, opts_i)

  local next_m = k.next_message or "]]"
  local prev_m = k.prev_message or "[["
  vim.keymap.set("n", next_m, function()
    require("pi.render").jump_message(chat, wins.chat, 1)
  end, opts_c)
  vim.keymap.set("n", prev_m, function()
    require("pi.render").jump_message(chat, wins.chat, -1)
  end, opts_c)

  vim.keymap.set("n", "q", function()
    M.close()
  end, opts_c)
end

local _open = M.open
function M.open()
  _open()
  pcall(map_ui_keys)
end

return M
