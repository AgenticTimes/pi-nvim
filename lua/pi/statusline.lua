-- Busy Working spinner for host statuslines (lualine) and the chat winbar
local M = {}

local FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local frame = 1
local started_at ---@type number|nil
local timer ---@type uv.uv_timer_t|nil

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

local function paint_chat_winbar(text)
  pcall(function()
    local win = require("pi.ui").chat_win()
    if not win or not vim.api.nvim_win_is_valid(win) then
      return
    end
    if text == "" then
      vim.wo[win].winbar = ""
    else
      vim.wo[win].winbar = "%#PiBusy#" .. text .. "%*"
    end
  end)
end

local function ensure_hl()
  if vim.fn.hlexists("PiBusy") == 0 then
    vim.api.nvim_set_hl(0, "PiBusy", { fg = 0xe0af68, bold = true })
  end
end

local function refresh()
  ensure_hl()
  local text = M.text()
  vim.g.pi_busy = text
  paint_chat_winbar(text)
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

function M.start()
  if started_at then
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
end

return M
