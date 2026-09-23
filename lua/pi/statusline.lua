-- Busy Working spinner: lualine + chat winbar + chat virt_lines footer
local M = {}

local FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local frame = 1
local started_at ---@type number|nil
local timer ---@type uv.uv_timer_t|nil
local busy_ns = vim.api.nvim_create_namespace("pi_busy")
local footer_mark ---@type integer|nil
local footer_buf ---@type integer|nil

local function close_timer()
  if not timer then
    return
  end
  if not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  timer = nil
end

local function ensure_hl()
  if vim.fn.hlexists("PiBusy") == 0 then
    vim.api.nvim_set_hl(0, "PiBusy", { fg = 0xe0af68, bold = true })
  end
end

local function clear_footer()
  if footer_buf and vim.api.nvim_buf_is_valid(footer_buf) then
    pcall(vim.api.nvim_buf_clear_namespace, footer_buf, busy_ns, 0, -1)
  end
  footer_mark = nil
  footer_buf = nil
end

--- Footer inside the chat buffer — always visible in the float, unlike statusline.
local function paint_chat_footer(text)
  local buf
  pcall(function()
    buf = require("pi.ui").chat_buf()
  end)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    clear_footer()
    return
  end
  if footer_buf and footer_buf ~= buf then
    clear_footer()
  end
  footer_buf = buf
  pcall(vim.api.nvim_buf_clear_namespace, buf, busy_ns, 0, -1)
  footer_mark = nil
  if text == "" then
    return
  end
  local last = math.max(0, vim.api.nvim_buf_line_count(buf) - 1)
  local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, busy_ns, last, 0, {
    virt_lines = { { { "  " .. text, "PiBusy" } } },
    virt_lines_above = false,
    priority = 200,
  })
  if ok then
    footer_mark = id
  end
end

local function paint_chat_winbar(text)
  pcall(function()
    local win = require("pi.ui").chat_win()
    if not win or not vim.api.nvim_win_is_valid(win) then
      return
    end
    local value = text == "" and "" or ("%#PiBusy#" .. text .. "%*")
    vim.api.nvim_set_option_value("winbar", value, { scope = "local", win = win })
  end)
end

local function refresh()
  ensure_hl()
  local text = M.text()
  vim.g.pi_busy = text
  paint_chat_winbar(text)
  paint_chat_footer(text)
  pcall(function()
    require("lualine").refresh({ place = { "statusline" } })
  end)
  pcall(vim.cmd.redrawstatus)
end

function M.text()
  if not started_at then
    return ""
  end
  local sec = math.max(0, math.floor((vim.uv.hrtime() - started_at) / 1e9))
  return string.format("%s Working · %ds", FRAMES[frame], sec)
end

function M.lualine()
  return M.text()
end

--- Re-paint onto the current chat window (after open / layout).
function M.repaint()
  if started_at then
    refresh()
  end
end

function M.start()
  if started_at then
    refresh()
    return
  end
  ensure_hl()
  started_at = vim.uv.hrtime()
  frame = 1
  close_timer()
  timer = vim.uv.new_timer()
  timer:start(100, 100, vim.schedule_wrap(function()
    if not started_at then
      return
    end
    frame = frame % #FRAMES + 1
    refresh()
  end))
  refresh()
end

function M.stop()
  if not started_at and not timer then
    return
  end
  started_at = nil
  frame = 1
  close_timer()
  refresh()
  clear_footer()
end

return M
