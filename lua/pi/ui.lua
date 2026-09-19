local config = require("pi.config")

local M = {}
local wins = { chat = nil, input = nil }
local bufs = { chat = nil, input = nil }

local function geometry()
  local w = math.floor(vim.o.columns * (config.opts.window.width or 0.4))
  local h = math.floor(vim.o.lines * (config.opts.window.height or 0.9))
  local input_h = math.max(5, math.floor(h * 0.2))
  local chat_h = h - input_h - 1
  local col = vim.o.columns - w - 1
  if config.opts.window.layout == "left" then
    col = 0
  elseif config.opts.window.layout == "center" then
    col = math.floor((vim.o.columns - w) / 2)
  end
  local row = math.max(0, math.floor((vim.o.lines - h) / 2))
  return {
    width = w,
    chat_h = chat_h,
    input_h = input_h,
    row = row,
    col = col,
    input_row = row + chat_h + 1,
  }
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
    return bufs.input
  end
  local input = require("pi.input")
  local b = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, b, "pi://input")
  input.setup(b, function()
    M.close()
  end)
  bufs.input = b
  return b
end

function M.is_open()
  return wins.chat ~= nil and vim.api.nvim_win_is_valid(wins.chat)
end

function M.open()
  if M.is_open() then
    vim.api.nvim_set_current_win(wins.input or wins.chat)
    vim.cmd("startinsert")
    return
  end
  require("pi.runtime").ensure_started()
  local g = geometry()
  local border = config.opts.window.border or "rounded"
  wins.chat = vim.api.nvim_open_win(M.chat_buf(), false, {
    relative = "editor",
    width = g.width,
    height = g.chat_h,
    row = g.row,
    col = g.col,
    style = "minimal",
    border = border,
    title = " pi chat ",
    title_pos = "center",
  })
  wins.input = vim.api.nvim_open_win(M.input_buf(), true, {
    relative = "editor",
    width = g.width,
    height = g.input_h,
    row = g.input_row,
    col = g.col,
    style = "minimal",
    border = border,
    title = " pi input ",
    title_pos = "center",
  })
  vim.cmd("startinsert")
end

function M.close()
  for _, w in pairs(wins) do
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
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

function M.on_event(ev)
  require("pi.render").on_event(M.chat_buf(), ev)
end

return M
