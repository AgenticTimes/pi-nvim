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

local function clear_pi_winbars()
  local seen = {}
  local function clear(win)
    if not win or seen[win] or not vim.api.nvim_win_is_valid(win) then
      return
    end
    seen[win] = true
    pcall(vim.api.nvim_set_option_value, "winbar", "", { scope = "local", win = win })
  end
  pcall(function()
    for _, win in ipairs(require("pi.slots").all_wins()) do
      clear(win)
    end
  end)
  pcall(function()
    clear(require("pi.ui").chat_win())
  end)
end

--- Wins that should show Working: only slots whose agent is busy.
local function busy_target_wins()
  local wins = {}
  pcall(function()
    wins = require("pi.slots").busy_wins()
  end)
  if #wins > 0 then
    return wins
  end
  -- Single-slot / status not synced yet: primary chat win only
  local win
  pcall(function()
    win = require("pi.ui").chat_win()
  end)
  if win and vim.api.nvim_win_is_valid(win) then
    return { win }
  end
  return {}
end

local function paint_overlay(text)
  local targets = busy_target_wins()
  local chat_win = targets[1]
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
  local line = "  " .. text
  local cur_line = ""
  if vim.api.nvim_buf_line_count(overlay_buf) >= 1 then
    cur_line = vim.api.nvim_buf_get_lines(overlay_buf, 0, 1, false)[1] or ""
  end
  if cur_line ~= line then
    vim.bo[overlay_buf].modifiable = true
    vim.api.nvim_buf_set_lines(overlay_buf, 0, -1, false, { line })
    vim.bo[overlay_buf].modifiable = false
  end

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
    -- Reconfig only when geometry drifted — set_config every 100ms shakes the float.
    local cur = vim.api.nvim_win_get_config(overlay_win)
    local same = cur.relative == "win"
      and cur.win == chat_win
      and cur.width == opts.width
      and cur.height == opts.height
      and cur.row == opts.row
      and cur.col == opts.col
    if not same then
      pcall(vim.api.nvim_win_set_config, overlay_win, opts)
    end
  else
    overlay_win = vim.api.nvim_open_win(overlay_buf, false, opts)
  end
  pcall(function()
    vim.wo[overlay_win].winhl = "Normal:PiBusyBar,NormalFloat:PiBusyBar"
  end)
end

--- Set winbar only when the string changes. Clearing then re-setting every
--- spinner tick grows/shrinks the content area by one row → vertical jitter.
local function paint_chat_winbar(text, busy)
  ensure_hl()
  local value = ""
  if text ~= "" then
    local hl = busy and "PiBusy" or "PiReview"
    value = "%#" .. hl .. "#" .. text .. "%*"
  end
  local targets
  if busy then
    targets = busy_target_wins()
  else
    -- Review cue: primary only
    targets = {}
    pcall(function()
      local win = require("pi.ui").chat_win()
      if win then
        targets = { win }
      end
    end)
  end
  local want = {}
  for _, win in ipairs(targets) do
    want[win] = true
    if vim.api.nvim_win_is_valid(win) then
      local cur = vim.api.nvim_get_option_value("winbar", { scope = "local", win = win })
      if cur ~= value then
        pcall(vim.api.nvim_set_option_value, "winbar", value, { scope = "local", win = win })
      end
    end
  end
  -- Drop stale winbars on other pi wins (only when they still have one).
  local function clear_if_stale(win)
    if not win or want[win] or not vim.api.nvim_win_is_valid(win) then
      return
    end
    local cur = vim.api.nvim_get_option_value("winbar", { scope = "local", win = win })
    if cur ~= "" then
      pcall(vim.api.nvim_set_option_value, "winbar", "", { scope = "local", win = win })
    end
  end
  pcall(function()
    for _, win in ipairs(require("pi.slots").all_wins()) do
      clear_if_stale(win)
    end
  end)
  pcall(function()
    clear_if_stale(require("pi.ui").chat_win())
  end)
end

local function refresh()
  ensure_hl()
  local text = M.text()
  vim.g.pi_busy = text
  -- Multi-slot: title already shows ●/activity. Overlay spans the full pane
  -- width and paints over the shared border + neighbor titles → looks "错位".
  local multi = false
  pcall(function()
    multi = require("pi.slots").count() > 1
  end)
  if multi then
    clear_pi_winbars()
    close_overlay()
    pcall(function()
      require("lualine").refresh({ place = { "statusline" } })
    end)
    pcall(vim.cmd.redrawstatus)
    return
  end
  if started_at then
    -- Busy: overlay only. Winbar + spinner-tick clear/set used to yank the
    -- chat content area by one row every 100ms (submit → wait jitter).
    paint_chat_winbar("", true)
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
