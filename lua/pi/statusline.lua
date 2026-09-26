-- Busy Working spinner + idle Review pending cue (lualine / winbar / overlay)
local M = {}

local FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local frame = 1
local started_at ---@type number|nil
local busy_label = "Working"
local timer ---@type uv.uv_timer_t|nil
local overlay_buf ---@type integer|nil
local overlay_win ---@type integer|nil

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
  if vim.fn.hlexists("PiReview") == 0 then
    vim.api.nvim_set_hl(0, "PiReview", { fg = 0xe0af68, bold = true })
  end
  if vim.fn.hlexists("PiBusyBar") == 0 then
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    local bg = normal.bg or 0x1a1b26
    vim.api.nvim_set_hl(0, "PiBusyBar", { fg = 0xe0af68, bg = bg, bold = true })
  end
end

local function close_overlay()
  if overlay_win and vim.api.nvim_win_is_valid(overlay_win) then
    pcall(vim.api.nvim_win_close, overlay_win, true)
  end
  overlay_win = nil
  if overlay_buf and vim.api.nvim_buf_is_valid(overlay_buf) then
    pcall(vim.api.nvim_buf_delete, overlay_buf, { force = true })
  end
  overlay_buf = nil
end

local function paint_overlay(text)
  local chat_win
  pcall(function()
    chat_win = require("pi.ui").chat_win()
  end)
  if not chat_win or not vim.api.nvim_win_is_valid(chat_win) or text == "" then
    close_overlay()
    return
  end
  ensure_hl()
  if not overlay_buf or not vim.api.nvim_buf_is_valid(overlay_buf) then
    overlay_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[overlay_buf].buftype = "nofile"
    vim.bo[overlay_buf].bufhidden = "wipe"
    vim.bo[overlay_buf].modifiable = true
  end
  vim.bo[overlay_buf].modifiable = true
  vim.api.nvim_buf_set_lines(overlay_buf, 0, -1, false, { "  " .. text })
  vim.bo[overlay_buf].modifiable = false

  local cfg = vim.api.nvim_win_get_config(chat_win)
  local width = cfg.width or vim.api.nvim_win_get_width(chat_win)
  local height = cfg.height or vim.api.nvim_win_get_height(chat_win)
  local opts = {
    relative = "win",
    win = chat_win,
    anchor = "SW",
    width = math.max(8, width),
    height = 1,
    row = height,
    col = 0,
    focusable = false,
    style = "minimal",
    border = "none",
    zindex = (cfg.zindex or 50) + 5,
  }
  if overlay_win and vim.api.nvim_win_is_valid(overlay_win) then
    pcall(vim.api.nvim_win_set_config, overlay_win, opts)
  else
    overlay_win = vim.api.nvim_open_win(overlay_buf, false, opts)
  end
  pcall(function()
    vim.wo[overlay_win].winhl = "Normal:PiBusyBar,NormalFloat:PiBusyBar"
  end)
end

local function paint_chat_winbar(text, busy)
  pcall(function()
    local win = require("pi.ui").chat_win()
    if not win or not vim.api.nvim_win_is_valid(win) then
      return
    end
    local hl = busy and "PiBusy" or "PiReview"
    local value = text == "" and "" or ("%#" .. hl .. "#" .. text .. "%*")
    vim.api.nvim_set_option_value("winbar", value, { scope = "local", win = win })
  end)
end

local function refresh()
  ensure_hl()
  local text = M.text()
  vim.g.pi_busy = text
  if started_at then
    paint_chat_winbar(text, true)
    paint_overlay(text)
  else
    -- idle: show pending Review in winbar; never keep the Working overlay
    paint_chat_winbar(text, false)
    close_overlay()
  end
  pcall(function()
    require("lualine").refresh({ place = { "statusline" } })
  end)
  pcall(vim.cmd.redrawstatus)
end

function M.text()
  if started_at then
    local sec = math.max(0, math.floor((vim.uv.hrtime() - started_at) / 1e9))
    return string.format("%s %s · %ds", FRAMES[frame], busy_label, sec)
  end
  local n = 0
  pcall(function()
    n = #require("pi.session").touched()
  end)
  if n > 0 then
    return string.format("Review · %d", n)
  end
  return ""
end

function M.lualine()
  return M.text()
end

function M.repaint()
  refresh()
end

---@param label string|nil e.g. "Working" or "Compacting"
function M.start(label)
  busy_label = label or "Working"
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
    -- still refresh so Review · N can appear after idle clears
    refresh()
    return
  end
  started_at = nil
  busy_label = "Working"
  frame = 1
  close_timer()
  refresh()
end

return M
