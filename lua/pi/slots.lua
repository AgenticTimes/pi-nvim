-- Multi-slot manager: primary + satellite translucent floats (M2)
local M = {}

---@class PiSlot
---@field id integer
---@field client table
---@field chat_buf integer
---@field win integer|nil
---@field status string
---@field is_default boolean

local slots = {} ---@type PiSlot[]
local primary_id ---@type integer|nil
local next_id = 1
local visible = false

local function max_slots()
  local n = require("pi.config").opts.max_slots
  if type(n) ~= "number" or n < 1 then
    return 4
  end
  return math.floor(n)
end

--- Singleton facade (`require("pi.client")`). Tests stub this table; do not
--- unwrap `.default()` or stubs lose `is_running`/`send`.
local function default_client()
  return require("pi.client")
end

local function chrome_rows()
  local cmd = math.max(0, vim.o.cmdheight or 0)
  local status = (vim.o.laststatus == 0) and 0 or 1
  local spare = (cmd == 0 and status > 0) and 1 or 0
  return cmd + status + spare
end

--- Pure layout math (testable). Focused master left (~68%); others stack right.
---@param opts { cols: integer, lines: integer, chrome?: integer, ids: integer[], primary: integer, margin?: integer }
---@return table<integer, { row: integer, col: integer, width: integer, height: integer, border: string, zindex: integer, focused: boolean }>
function M.compute_layout(opts)
  local cols = opts.cols
  local lines = opts.lines
  local chrome = opts.chrome or 2
  local margin = opts.margin or 1
  local ids = opts.ids
  local primary = opts.primary
  local usable_h = math.max(8, lines - chrome - 2 * margin)
  local usable_w = math.max(20, cols - 2 * margin)
  local sats = {}
  for _, id in ipairs(ids) do
    if id ~= primary then
      sats[#sats + 1] = id
    end
  end
  local out = {}
  if #sats == 0 then
    out[primary] = {
      row = margin,
      col = margin,
      width = usable_w,
      height = usable_h,
      border = "rounded",
      zindex = 52,
      focused = true,
    }
    return out
  end
  local gap = 1
  -- Side stack: readable mini panes; master takes the rest and full height.
  local stack_w = math.max(22, math.min(math.floor(usable_w * 0.34), math.floor(usable_w * 0.42)))
  local master_w = math.max(24, usable_w - stack_w - gap)
  local n = #sats
  local cell_h = math.max(5, math.floor((usable_h - (n - 1) * gap) / n))
  for i, id in ipairs(sats) do
    local row = margin + (i - 1) * (cell_h + gap)
    local h = cell_h
    if i == n then
      h = math.max(5, usable_h - (row - margin))
    end
    out[id] = {
      row = row,
      col = margin + master_w + gap,
      width = stack_w,
      height = h,
      border = "rounded",
      zindex = 48,
      focused = false,
    }
  end
  out[primary] = {
    row = margin,
    col = margin,
    width = master_w,
    height = usable_h,
    border = "rounded",
    zindex = 52,
    focused = true,
  }
  return out
end

local function find(id)
  for _, s in ipairs(slots) do
    if s.id == id then
      return s
    end
  end
  return nil
end

local function ids()
  local out = {}
  for _, s in ipairs(slots) do
    out[#out + 1] = s.id
  end
  return out
end

local function make_chat_buf(name)
  local render = require("pi.render")
  local b = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, b, name)
  render.setup(b)
  render.reset(b)
  return b
end

local focus_autocmd ---@type integer|nil

local function title_for(slot)
  local busy = slot.status == "busy" or slot.status == "streaming"
  local dot = busy and "●" or "○"
  if slot.id == primary_id then
    return string.format(" %s #%d · focus ", dot, slot.id)
  end
  return string.format(" %s #%d ", dot, slot.id)
end

local function ensure_slot_hl()
  -- Focus: bright blue border; idle: muted gray
  vim.api.nvim_set_hl(0, "PiSlotFocusBorder", { fg = 0x7aa2f7, bold = true })
  vim.api.nvim_set_hl(0, "PiSlotIdleBorder", { fg = 0x565f89 })
  vim.api.nvim_set_hl(0, "PiSlotFocusTitle", { fg = 0x7aa2f7, bold = true })
  vim.api.nvim_set_hl(0, "PiSlotIdleTitle", { fg = 0x565f89 })
end

---@param focused boolean
local function border_for(focused)
  local hl = focused and "PiSlotFocusBorder" or "PiSlotIdleBorder"
  return {
    { "╭", hl },
    { "─", hl },
    { "╮", hl },
    { "│", hl },
    { "╯", hl },
    { "─", hl },
    { "╰", hl },
    { "│", hl },
  }
end

--- Any slot window can interact: focus → primary, Enter → ask that agent.
local function map_slot_keys(slot)
  local buf = slot.chat_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if vim.b[buf].pi_slot_keys then
    return
  end
  vim.b[buf].pi_slot_keys = true
  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", function()
    M.set_primary(slot.id)
    local win = slot.win
    if require("pi.render").toggle_tool_at_cursor(slot.chat_buf, win) then
      return
    end
    require("pi.ui").open_input()
  end, vim.tbl_extend("force", opts, { desc = "pi: focus slot + ask" }))
  vim.keymap.set("n", "za", function()
    M.set_primary(slot.id)
    require("pi.render").toggle_tool_at_cursor(slot.chat_buf, slot.win)
  end, vim.tbl_extend("force", opts, { desc = "pi: toggle tool expand" }))
  vim.keymap.set("n", "q", function()
    M.hide()
  end, vim.tbl_extend("force", opts, { desc = "pi: hide slots" }))
  local k = require("pi.config").opts.keys or {}
  local next_m = k.next_message or "]]"
  local prev_m = k.prev_message or "[["
  vim.keymap.set("n", next_m, function()
    M.set_primary(slot.id)
    require("pi.render").jump_message(slot.chat_buf, slot.win, 1)
  end, opts)
  vim.keymap.set("n", prev_m, function()
    M.set_primary(slot.id)
    require("pi.render").jump_message(slot.chat_buf, slot.win, -1)
  end, opts)
end

local function ensure_focus_autocmd()
  if focus_autocmd then
    return
  end
  focus_autocmd = vim.api.nvim_create_autocmd("WinEnter", {
    callback = function()
      if not visible or #slots < 2 then
        return
      end
      local win = vim.api.nvim_get_current_win()
      for _, s in ipairs(slots) do
        if s.win == win and s.id ~= primary_id then
          M.set_primary(s.id)
          return
        end
      end
    end,
  })
end

local function configure_win(win, focused)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].signcolumn = "no"
  local base = tonumber((require("pi.config").opts.window or {}).winblend) or 18
  local blend = focused and math.max(0, base - 6) or math.min(40, base + 12)
  pcall(function()
    vim.wo[win].winblend = blend
  end)
  local border_hl = focused and "PiSlotFocusBorder" or "PiSlotIdleBorder"
  pcall(function()
    vim.wo[win].winhl = "Normal:PiChatNormal,NormalFloat:PiChatNormal,FloatBorder:" .. border_hl
  end)
end

local function satellite_on_event(slot, ev)
  local prev = slot.status
  if ev.type == "agent_start" or ev.type == "turn_start" then
    slot.status = "busy"
  elseif ev.type == "agent_end" or ev.type == "agent_settled" then
    slot.status = "idle"
  end
  pcall(function()
    require("pi.render").on_event(slot.chat_buf, ev)
  end)
  if slot.win and vim.api.nvim_win_is_valid(slot.win) then
    pcall(vim.api.nvim_win_set_config, slot.win, { title = title_for(slot), title_pos = "center" })
  end
  if prev ~= slot.status then
    pcall(function()
      require("pi.statusline").repaint()
    end)
  end
end

local function bind_primary(slot)
  require("pi.runtime").bind_events(slot.client)
end

local function bind_satellite(slot)
  slot.client.set_on_event(function(ev)
    satellite_on_event(slot, ev)
  end)
end

function M.list()
  return vim.deepcopy(slots)
end

--- Live slot refs (for statusline win targeting).
function M.live()
  return slots
end

function M.all_wins()
  local wins = {}
  for _, s in ipairs(slots) do
    if s.win and vim.api.nvim_win_is_valid(s.win) then
      wins[#wins + 1] = s.win
    end
  end
  return wins
end

--- Windows whose agent is actually busy (not merely focused).
function M.busy_wins()
  local wins = {}
  for _, s in ipairs(slots) do
    if (s.status == "busy" or s.status == "streaming") and s.win and vim.api.nvim_win_is_valid(s.win) then
      wins[#wins + 1] = s.win
    end
  end
  return wins
end

--- Keep primary slot.status in sync with singleton session (tools path).
function M.sync_primary_status()
  local p = M.primary()
  if not p then
    return
  end
  local st = "idle"
  pcall(function()
    st = require("pi.session").get().status
  end)
  local next_status = (st == "streaming" or st == "compacting") and "busy" or "idle"
  if p.status == next_status then
    return
  end
  p.status = next_status
  if p.win and vim.api.nvim_win_is_valid(p.win) then
    pcall(vim.api.nvim_win_set_config, p.win, { title = title_for(p), title_pos = "center" })
  end
end

function M.count()
  return #slots
end

function M.primary()
  return primary_id and find(primary_id) or nil
end

function M.primary_client()
  local s = M.primary()
  -- Default slot always resolves live (tests stub package.loaded["pi.client"]).
  if not s or s.is_default then
    return default_client()
  end
  return s.client
end

function M.primary_chat_buf()
  local s = M.primary()
  if s and s.chat_buf and vim.api.nvim_buf_is_valid(s.chat_buf) then
    return s.chat_buf
  end
  return require("pi.ui").chat_buf()
end

--- Ensure default slot (singleton client + ui chat buf).
function M.ensure_default()
  if #slots > 0 then
    return find(primary_id) or slots[1]
  end
  local client = default_client()
  local buf = require("pi.ui").chat_buf()
  local slot = {
    id = next_id,
    client = client,
    chat_buf = buf,
    win = nil,
    status = "idle",
    is_default = true,
  }
  next_id = next_id + 1
  slots[1] = slot
  primary_id = slot.id
  map_slot_keys(slot)
  ensure_focus_autocmd()
  return slot
end

--- Create a new satellite slot (new pi job). Returns slot or nil, err.
function M.create()
  M.ensure_default()
  if #slots >= max_slots() then
    return nil, "max slots (" .. tostring(max_slots()) .. ")"
  end
  local id = next_id
  next_id = next_id + 1
  local client = require("pi.client").new()
  local buf = make_chat_buf("pi://chat/" .. tostring(id))
  local slot = {
    id = id,
    client = client,
    chat_buf = buf,
    win = nil,
    status = "idle",
    is_default = false,
  }
  slots[#slots + 1] = slot
  map_slot_keys(slot)
  ensure_focus_autocmd()
  bind_satellite(slot)
  local ok, err = pcall(function()
    require("pi.runtime").start_job(client, {
      on_event = function(ev)
        satellite_on_event(slot, ev)
      end,
    })
  end)
  if not ok then
    slots[#slots] = nil
    pcall(client.stop)
    return nil, tostring(err)
  end
  if visible then
    M.show()
  end
  vim.notify("pi: slot #" .. tostring(id) .. " started", vim.log.levels.INFO)
  return slot
end

function M.close(id)
  id = id or primary_id
  local slot = find(id)
  if not slot then
    return false
  end
  if slot.is_default and #slots > 1 then
    vim.notify("pi: close other slots first (or keep default)", vim.log.levels.WARN)
    return false
  end
  if #slots == 1 and slot.is_default then
    -- hide UI only; keep default job
    M.hide()
    return true
  end
  if slot.win and vim.api.nvim_win_is_valid(slot.win) then
    pcall(vim.api.nvim_win_close, slot.win, true)
  end
  if not slot.is_default then
    pcall(slot.client.stop)
  end
  local kept = {}
  for _, s in ipairs(slots) do
    if s.id ~= id then
      kept[#kept + 1] = s
    end
  end
  slots = kept
  if primary_id == id then
    primary_id = slots[1] and slots[1].id or nil
    local p = M.primary()
    if p then
      bind_primary(p)
    end
  end
  if visible then
    if #slots <= 1 then
      M.hide()
      require("pi.ui").open()
      visible = true
    else
      M.apply_layout()
    end
  end
  return true
end

function M.set_primary(id)
  local slot = find(id)
  if not slot then
    return false
  end
  if primary_id == id then
    return true
  end
  local old = M.primary()
  if old then
    bind_satellite(old)
  end
  primary_id = id
  bind_primary(slot)
  require("pi.ui").adopt_chat_buf(slot.chat_buf)
  if visible then
    M.apply_layout()
    if slot.win and vim.api.nvim_win_is_valid(slot.win) then
      vim.api.nvim_set_current_win(slot.win)
    end
  end
  return true
end

function M.cycle_primary(dir)
  if #slots < 2 then
    return false
  end
  dir = dir or 1
  local idx = 1
  for i, s in ipairs(slots) do
    if s.id == primary_id then
      idx = i
      break
    end
  end
  local next_idx = ((idx - 1 + dir) % #slots) + 1
  return M.set_primary(slots[next_idx].id)
end

function M.apply_layout()
  if #slots == 0 then
    return
  end
  ensure_slot_hl()
  local layout = M.compute_layout({
    cols = vim.o.columns,
    lines = vim.o.lines,
    chrome = chrome_rows(),
    ids = ids(),
    primary = primary_id,
  })
  local ui = require("pi.ui")
  for _, slot in ipairs(slots) do
    local g = layout[slot.id]
    if g then
      local focused = slot.id == primary_id
      local cfg = {
        relative = "editor",
        width = g.width,
        height = g.height,
        row = g.row,
        col = g.col,
        style = "minimal",
        border = border_for(focused),
        title = title_for(slot),
        title_pos = "center",
        zindex = g.zindex,
      }
      if slot.win and vim.api.nvim_win_is_valid(slot.win) then
        pcall(vim.api.nvim_win_set_config, slot.win, cfg)
      else
        slot.win = vim.api.nvim_open_win(slot.chat_buf, focused, cfg)
      end
      configure_win(slot.win, focused)
      if focused then
        ui.adopt_chat_win(slot.win, slot.chat_buf)
        pcall(function()
          require("pi.render").attach_scroll(slot.win, slot.chat_buf)
          require("pi.render").follow(slot.chat_buf, true, slot.win)
        end)
      end
    end
  end
  pcall(function()
    require("pi.statusline").repaint()
  end)
end

function M.show()
  M.ensure_default()
  require("pi.runtime").ensure_started()
  local p = M.primary()
  if p then
    bind_primary(p)
    require("pi.ui").adopt_chat_buf(p.chat_buf)
  end
  -- ui.open paints primary buf; apply_layout resizes + opens satellites
  require("pi.ui").open()
  if p then
    p.win = require("pi.ui").chat_win()
  end
  visible = true
  if #slots > 1 then
    M.apply_layout()
  end
end

function M.hide()
  for _, slot in ipairs(slots) do
    if not slot.is_default and slot.win and vim.api.nvim_win_is_valid(slot.win) then
      pcall(vim.api.nvim_win_close, slot.win, true)
    end
    if not slot.is_default then
      slot.win = nil
    end
  end
  require("pi.ui").close()
  for _, slot in ipairs(slots) do
    slot.win = nil
  end
  visible = false
end

function M.is_visible()
  if #slots <= 1 then
    return require("pi.ui").is_open()
  end
  return visible
end

function M.toggle_visible()
  if M.is_visible() then
    M.hide()
  else
    M.show()
  end
end

--- Reset module state (tests).
function M._reset_for_test()
  for _, s in ipairs(slots) do
    if s.win and vim.api.nvim_win_is_valid(s.win) then
      pcall(vim.api.nvim_win_close, s.win, true)
    end
    if not s.is_default then
      pcall(s.client.stop)
    end
  end
  slots = {}
  primary_id = nil
  next_id = 1
  visible = false
end

return M
