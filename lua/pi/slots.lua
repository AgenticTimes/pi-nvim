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
    return 24
  end
  return math.floor(n)
end

local function slot_mins()
  local o = require("pi.config").opts
  local mw = o.slot_min_width
  local mh = o.slot_min_height
  if type(mw) ~= "number" or mw < 8 then
    mw = 24
  end
  if type(mh) ~= "number" or mh < 3 then
    mh = 6
  end
  return math.floor(mw), math.floor(mh)
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

--- How many min-sized cells fit (vertical first, then horizontal).
---@param opts { cols: integer, lines: integer, chrome?: integer, margin?: integer, min_w?: integer, min_h?: integer }
---@return integer
function M.capacity(opts)
  local gap = 1
  local chrome = opts.chrome or 2
  local margin = opts.margin or 1
  local min_w = opts.min_w
  local min_h = opts.min_h
  if not min_w or not min_h then
    min_w, min_h = slot_mins()
  end
  local usable_h = math.max(min_h, (opts.lines or 40) - chrome - 2 * margin)
  local usable_w = math.max(min_w, (opts.cols or 80) - 2 * margin)
  local rows = math.max(1, math.floor((usable_h + gap) / (min_h + gap)))
  local cols_n = math.max(1, math.floor((usable_w + gap) / (min_w + gap)))
  return math.min(max_slots(), rows * cols_n)
end

--- Pack `id_list` into a rectangle as a grid: fill rows (vertical) up to
--- max_rows at min_h, then add columns (horizontal split).
local function place_grid(id_list, row0, col0, w, h, gap, min_w, min_h, primary, out)
  local n = #id_list
  if n == 0 then
    return
  end
  local max_rows = math.max(1, math.floor((h + gap) / (min_h + gap)))
  local rows = math.min(n, max_rows)
  local cols_n = math.ceil(n / rows)
  local col_w = math.max(1, math.floor((w - (cols_n - 1) * gap) / cols_n))
  local cell_h = math.max(1, math.floor((h - (rows - 1) * gap) / rows))
  for i, id in ipairs(id_list) do
    local col_i = (i - 1) % cols_n
    local row_i = math.floor((i - 1) / cols_n)
    local row = row0 + row_i * (cell_h + gap)
    local col = col0 + col_i * (col_w + gap)
    local cw = col_w
    local ch = cell_h
    if col_i == cols_n - 1 then
      cw = math.max(1, w - col_i * (col_w + gap))
    end
    if row_i == rows - 1 then
      ch = math.max(1, h - row_i * (cell_h + gap))
    end
    local focused = id == primary
    out[id] = {
      row = row,
      col = col,
      width = cw,
      height = ch,
      border = "rounded",
      zindex = focused and 52 or 48,
      focused = focused,
    }
  end
end

--- Pure layout math (testable).
--- Primary (master) stays left while space allows; satellites pack right
--- with vertical-first then horizontal splits at slot_min_*.
---@param opts { cols: integer, lines: integer, chrome?: integer, ids: integer[], primary: integer, margin?: integer, min_w?: integer, min_h?: integer }
---@return table<integer, { row: integer, col: integer, width: integer, height: integer, border: string, zindex: integer, focused: boolean }>
function M.compute_layout(opts)
  local cols = opts.cols
  local lines = opts.lines
  local chrome = opts.chrome or 2
  local margin = opts.margin or 1
  local ids = opts.ids
  local primary = opts.primary
  local min_w = opts.min_w
  local min_h = opts.min_h
  if not min_w or not min_h then
    min_w, min_h = slot_mins()
  end
  local usable_h = math.max(min_h, lines - chrome - 2 * margin)
  local usable_w = math.max(min_w, cols - 2 * margin)
  local gap = 1
  local out = {}
  local sats = {}
  for _, id in ipairs(ids) do
    if id ~= primary then
      sats[#sats + 1] = id
    end
  end
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

  local n = #sats
  local max_rows = math.max(1, math.floor((usable_h + gap) / (min_h + gap)))
  local stack_rows = math.min(n, max_rows)
  local stack_cols = math.ceil(n / stack_rows)
  local need_stack_w = stack_cols * min_w + (stack_cols - 1) * gap

  -- Master + right pack when both sides can keep min width
  if need_stack_w + gap + min_w <= usable_w then
    -- Prefer a readable stack when few cols; extra width goes to master.
    local preferred = math.max(need_stack_w, math.floor(usable_w * math.min(0.48, 0.20 + stack_cols * 0.10)))
    local stack_w = math.min(preferred, usable_w - min_w - gap)
    stack_w = math.max(need_stack_w, stack_w)
    local master_w = usable_w - stack_w - gap
    out[primary] = {
      row = margin,
      col = margin,
      width = master_w,
      height = usable_h,
      border = "rounded",
      zindex = 52,
      focused = true,
    }
    place_grid(sats, margin, margin + master_w + gap, stack_w, usable_h, gap, min_w, min_h, primary, out)
    return out
  end

  -- Screen full at min grain: equal grid of every slot (primary is just one cell)
  place_grid(ids, margin, margin, usable_w, usable_h, gap, min_w, min_h, primary, out)
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

local function session_label(slot)
  local name = slot.session_name
  if (not name or name == "") and slot.id == primary_id then
    pcall(function()
      name = require("pi.session").get().session_name
    end)
  end
  if not name or name == "" then
    return nil
  end
  name = tostring(name):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #name > 28 then
    name = name:sub(1, 27) .. "…"
  end
  return name
end

-- Distinct border colors per slot id (cycle). Focus = brighter + bold.
local SLOT_COLORS = {
  { idle = 0x7aa2f7, focus = 0x89b4fa }, -- blue
  { idle = 0x9ece6a, focus = 0xb9f27c }, -- green
  { idle = 0xe0af68, focus = 0xffc777 }, -- amber
  { idle = 0xbb9af7, focus = 0xd4bfff }, -- purple
  { idle = 0x7dcfff, focus = 0xa6eaff }, -- cyan
  { idle = 0xf7768e, focus = 0xff9db0 }, -- rose
}

local function color_index(slot_id)
  local n = #SLOT_COLORS
  return ((math.max(1, slot_id or 1) - 1) % n) + 1
end

local function border_hl_name(slot_id, focused)
  local i = color_index(slot_id)
  if focused then
    return "PiSlotBorder" .. i .. "Focus"
  end
  return "PiSlotBorder" .. i
end

local function ensure_slot_hl()
  for i, c in ipairs(SLOT_COLORS) do
    vim.api.nvim_set_hl(0, "PiSlotBorder" .. i, { fg = c.idle })
    vim.api.nvim_set_hl(0, "PiSlotBorder" .. i .. "Focus", { fg = c.focus, bold = true })
  end
end

local slot_hl_autocmd ---@type integer|nil
local function ensure_slot_hl_autocmd()
  if slot_hl_autocmd then
    return
  end
  slot_hl_autocmd = vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
      ensure_slot_hl()
      if visible then
        M.apply_layout()
      end
    end,
  })
end

---@param slot PiSlot
---@param focused boolean
local function border_for(slot, focused)
  local hl = border_hl_name(slot.id, focused)
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

local function title_for(slot)
  local busy = slot.status == "busy" or slot.status == "streaming"
  local dot = busy and "●" or "○"
  local name = session_label(slot)
  local focus = slot.id == primary_id and " · focus" or ""
  if name then
    return string.format(" %s #%d · %s%s ", dot, slot.id, name, focus)
  end
  return string.format(" %s #%d%s ", dot, slot.id, focus)
end

local function refresh_slot_title(slot)
  if slot.win and vim.api.nvim_win_is_valid(slot.win) then
    local focused = slot.id == primary_id
    pcall(vim.api.nvim_win_set_config, slot.win, {
      title = title_for(slot),
      title_pos = "center",
      border = border_for(slot, focused),
    })
  end
end

local function apply_slot_state(slot, data)
  if type(data) ~= "table" then
    return
  end
  if data.sessionName and data.sessionName ~= "" then
    slot.session_name = data.sessionName
  end
  if data.isStreaming then
    slot.status = "busy"
  elseif data.isStreaming == false and not data.isCompacting then
    slot.status = "idle"
  end
  refresh_slot_title(slot)
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
  vim.keymap.set("n", "ftc", function()
    M.set_primary(slot.id)
    require("pi.render").toggle_fold_kind(slot.chat_buf, "tool")
  end, vim.tbl_extend("force", opts, { desc = "pi: fold/unfold toolcalls" }))
  vim.keymap.set("n", "ftk", function()
    M.set_primary(slot.id)
    require("pi.render").toggle_fold_kind(slot.chat_buf, "thinking")
  end, vim.tbl_extend("force", opts, { desc = "pi: fold/unfold thinking" }))
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

local function configure_win(win, slot, focused)
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
  local border_hl = border_hl_name(slot.id, focused)
  pcall(function()
    vim.wo[win].winhl = "Normal:PiChatNormal,NormalFloat:PiChatNormal,FloatBorder:" .. border_hl
  end)
end

local function sole_busy_slot()
  local busy ---@type PiSlot|nil
  for _, s in ipairs(slots) do
    if s.status == "busy" or s.status == "streaming" then
      if busy then
        return nil
      end
      busy = s
    end
  end
  return busy
end

local function any_busy_aside(except_id)
  for _, s in ipairs(slots) do
    if s.id ~= except_id and (s.status == "busy" or s.status == "streaming") then
      return s
    end
  end
  return nil
end

--- If master is idle, give the large pane to a responding slot.
local function maybe_auto_promote(from_slot)
  if #slots < 2 or not visible then
    return
  end
  local primary = M.primary()
  if not primary then
    return
  end
  local primary_busy = primary.status == "busy" or primary.status == "streaming"
  -- Master still working → keep it large
  if primary_busy then
    return
  end
  -- Master idle → enlarge the responding slot (prefer the one that just fired)
  local target = from_slot
  if not target or (target.status ~= "busy" and target.status ~= "streaming") then
    target = sole_busy_slot() or any_busy_aside(primary.id)
  end
  if not target or target.id == primary.id then
    return
  end
  if target.status ~= "busy" and target.status ~= "streaming" then
    return
  end
  vim.schedule(function()
    if not visible then
      return
    end
    local p = M.primary()
    if p and (p.status == "busy" or p.status == "streaming") then
      return
    end
    if target.status == "busy" or target.status == "streaming" then
      M.set_primary(target.id)
    end
  end)
end

local function satellite_on_event(slot, ev)
  local prev = slot.status
  local activity = false
  if ev.type == "agent_start" or ev.type == "turn_start" then
    slot.status = "busy"
    activity = true
  elseif ev.type == "message_update" or ev.type == "tool_execution_start" then
    -- Receiving a response: treat as working even if agent_start was missed
    if slot.status ~= "busy" then
      slot.status = "busy"
    end
    activity = true
  elseif ev.type == "agent_end" or ev.type == "agent_settled" then
    slot.status = "idle"
    activity = true
  elseif ev.type == "response" and ev.success and ev.data then
    if ev.command == "get_state" or ev.command == "set_session_name" then
      apply_slot_state(slot, ev.data)
      activity = true
    end
  end
  pcall(function()
    require("pi.render").on_event(slot.chat_buf, ev)
  end)
  refresh_slot_title(slot)
  if prev ~= slot.status then
    pcall(function()
      require("pi.statusline").repaint()
    end)
  end
  if activity then
    maybe_auto_promote(slot)
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

--- Keep primary slot.status / name in sync with singleton session.
function M.sync_primary_status()
  local p = M.primary()
  if not p then
    return
  end
  local st = "idle"
  local name
  pcall(function()
    local g = require("pi.session").get()
    st = g.status
    name = g.session_name
  end)
  if name and name ~= "" then
    p.session_name = name
  end
  local prev = p.status
  p.status = (st == "streaming" or st == "compacting") and "busy" or "idle"
  refresh_slot_title(p)
  if prev ~= p.status then
    pcall(function()
      require("pi.statusline").repaint()
    end)
    -- Master went idle while a satellite still responds → enlarge that one
    maybe_auto_promote(p)
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
    session_name = nil,
    is_default = true,
  }
  next_id = next_id + 1
  slots[1] = slot
  primary_id = slot.id
  map_slot_keys(slot)
  ensure_focus_autocmd()
  pcall(function()
    local n = require("pi.session").get().session_name
    if n and n ~= "" then
      slot.session_name = n
    end
  end)
  return slot
end

--- Create a new satellite slot (new pi job). Returns slot or nil, err.
function M.create()
  M.ensure_default()
  local cap = M.capacity({
    cols = vim.o.columns,
    lines = vim.o.lines,
    chrome = chrome_rows(),
  })
  if #slots >= cap then
    return nil, string.format("no room (capacity %d at min cell); close one with a_", cap)
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
    session_name = nil,
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
  -- Ask RPC for session name / busy flags
  pcall(function()
    client.send({ type = "get_state", id = "slot-state-" .. tostring(id) })
  end)
  -- Shrink the master (largest) float; new slot joins the right stack
  if visible or require("pi.ui").is_open() then
    visible = true
    local p = M.primary()
    if p and (not p.win or not vim.api.nvim_win_is_valid(p.win)) then
      p.win = require("pi.ui").chat_win()
    end
    M.apply_layout()
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
  ensure_slot_hl_autocmd()
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
        border = border_for(slot, focused),
        title = title_for(slot),
        title_pos = "center",
        zindex = g.zindex,
      }
      if slot.win and vim.api.nvim_win_is_valid(slot.win) then
        pcall(vim.api.nvim_win_set_config, slot.win, cfg)
      else
        slot.win = vim.api.nvim_open_win(slot.chat_buf, focused, cfg)
      end
      configure_win(slot.win, slot, focused)
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
  -- ui.open paints primary buf; apply_layout applies per-slot colored borders
  require("pi.ui").open()
  if p then
    p.win = require("pi.ui").chat_win()
  end
  visible = true
  M.apply_layout()
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
