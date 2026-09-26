-- Multi-slot manager: primary + satellite translucent floats (M2)
local M = {}

---@class PiSlot
---@field id integer
---@field client table
---@field chat_buf integer
---@field win integer|nil
---@field status string
---@field is_default boolean
---@field session_name string|nil
---@field goal string|nil user objective (title layer 1)
---@field activity string|nil current action (title layer 2)
---@field parked boolean|nil hidden while idle (toggle_idle)

local slots = {} ---@type PiSlot[]
local primary_id ---@type integer|nil
local next_id = 1
local visible = false

local function max_slots()
  local n = require("pi.config").opts.max_slots
  if type(n) ~= "number" or n < 1 then
    return 64
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

--- How many slots fit when master shrinks to min_w and the rest is a
--- vertical-first satellite grid (also consider equal full-screen grid).
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
  -- Equal grid across the whole editor
  local full_cols = math.max(1, math.floor((usable_w + gap) / (min_w + gap)))
  local equal = rows * full_cols
  -- Master at minimum width; pack satellites in the remaining strip
  local stacked = 1
  local stack_w = usable_w - min_w - gap
  if stack_w >= min_w then
    local stack_cols = math.max(1, math.floor((stack_w + gap) / (min_w + gap)))
    stacked = 1 + rows * stack_cols
  end
  return math.min(max_slots(), math.max(equal, stacked))
end

--- Split `total` into `n` sizes with `gap` between them (exact fill).
local function split_sizes(total, n, gap)
  n = math.max(1, n)
  local inner = math.max(n, total - (n - 1) * gap)
  local base = math.floor(inner / n)
  local rem = inner - base * n
  local sizes = {}
  for i = 1, n do
    sizes[i] = base + (i <= rem and 1 or 0)
  end
  return sizes
end

--- Pack `id_list` into a rectangle. Each row shares full width (last row
--- stretches) so the grid has no empty holes.
local function place_grid(id_list, row0, col0, w, h, gap, min_w, min_h, primary, out)
  local n = #id_list
  if n == 0 then
    return
  end
  local max_rows = math.max(1, math.floor((h + gap) / (math.max(1, min_h) + gap)))
  local rows = math.min(n, max_rows)
  local cols_n = math.ceil(n / rows)
  local row_heights = split_sizes(h, rows, gap)
  local idx = 1
  local y = row0
  for r = 1, rows do
    local row_count = math.min(cols_n, n - idx + 1)
    local col_widths = split_sizes(w, row_count, gap)
    local x = col0
    local ch = row_heights[r]
    for c = 1, row_count do
      local id = id_list[idx]
      local focused = id == primary
      out[id] = {
        row = y,
        col = x,
        width = col_widths[c],
        height = ch,
        border = "single",
        -- Above master so shared-edge tees (┬├) paint over master's │
        zindex = focused and 52 or 50,
        focused = focused,
      }
      x = x + col_widths[c] + gap
      idx = idx + 1
    end
    y = y + ch + gap
  end
end

local function rows_overlap(a, b)
  return a.row < b.row + b.height and b.row < a.row + a.height
end

local function cols_overlap(a, b)
  return a.col < b.col + b.width and b.col < a.col + a.width
end

--- Mark nbr.{N,S,E,W} so borders can share an edge without ┐┌ seams.
local function annotate_neighbors(out, gap)
  gap = gap or 1
  local list = {}
  for id, g in pairs(out) do
    g.nbr = { N = false, S = false, E = false, W = false }
    list[#list + 1] = g
  end
  for i = 1, #list do
    for j = i + 1, #list do
      local a, b = list[i], list[j]
      if b.col == a.col + a.width + gap and rows_overlap(a, b) then
        a.nbr.E = true
        b.nbr.W = true
      elseif a.col == b.col + b.width + gap and rows_overlap(a, b) then
        b.nbr.E = true
        a.nbr.W = true
      end
      if b.row == a.row + a.height + gap and cols_overlap(a, b) then
        a.nbr.S = true
        b.nbr.N = true
      elseif a.row == b.row + b.height + gap and cols_overlap(a, b) then
        b.nbr.S = true
        a.nbr.N = true
      end
    end
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
      border = "single",
      zindex = 52,
      focused = true,
    }
    annotate_neighbors(out, gap)
    return out
  end

  local n = #sats
  local max_rows = math.max(1, math.floor((usable_h + gap) / (min_h + gap)))
  local stack_rows = math.min(n, max_rows)
  local stack_cols = math.ceil(n / stack_rows)
  local need_stack_w = stack_cols * min_w + (stack_cols - 1) * gap

  -- Master + right pack when both sides can keep min width
  if need_stack_w + gap + min_w <= usable_w then
    local steal = math.min(0.78, 0.22 + stack_cols * 0.14 + (n > 4 and (n - 4) * 0.03 or 0))
    local preferred = math.max(need_stack_w, math.floor(usable_w * steal))
    local stack_w = math.min(preferred, usable_w - min_w - gap)
    stack_w = math.max(need_stack_w, stack_w)
    local master_w = usable_w - stack_w - gap
    out[primary] = {
      row = margin,
      col = margin,
      width = master_w,
      height = usable_h,
      border = "single",
      zindex = 49,
      focused = true,
    }
    place_grid(sats, margin, margin + master_w + gap, stack_w, usable_h, gap, min_w, min_h, primary, out)
    annotate_neighbors(out, gap)
    return out
  end

  -- Screen full at min grain: equal grid of every slot (primary is just one cell)
  place_grid(ids, margin, margin, usable_w, usable_h, gap, min_w, min_h, primary, out)
  annotate_neighbors(out, gap)
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

local function slot_busy(s)
  return s.status == "busy" or s.status == "streaming"
end

--- Slot ids participating in the float layout (excludes parked idle).
local function layout_ids()
  local out = {}
  for _, s in ipairs(slots) do
    if not s.parked then
      out[#out + 1] = s.id
    end
  end
  return out
end

--- True when the chat buffer has real transcript (not just the empty header).
local function slot_has_content(s)
  if not s then
    return false
  end
  if (s.goal and s.goal ~= "") or (s.activity and s.activity ~= "") then
    return true
  end
  if s.session_name and s.session_name ~= "" then
    return true
  end
  local buf = s.chat_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local n = vim.api.nvim_buf_line_count(buf)
  if n <= 1 then
    local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    return line ~= "" and not line:match("^#?%s*pi%s")
  end
  return n > 2
end

--- Priority for layout placement: busy > has content > idle.
---@param s PiSlot|nil
---@return integer
function M.layout_priority(s)
  if not s then
    return 0
  end
  if slot_busy(s) then
    return 3
  end
  if slot_has_content(s) then
    return 2
  end
  return 1
end

--- Sort ids: higher priority first (busy/content → top-left), then lower id.
---@param ids integer[]
---@param priority_of fun(id: integer): integer
---@return integer[]
function M.sort_ids_by_priority(ids, priority_of)
  local scored = {}
  for _, id in ipairs(ids) do
    scored[#scored + 1] = { id = id, p = priority_of(id) or 0 }
  end
  table.sort(scored, function(a, b)
    if a.p ~= b.p then
      return a.p > b.p
    end
    return a.id < b.id
  end)
  local out = {}
  for _, x in ipairs(scored) do
    out[#out + 1] = x.id
  end
  return out
end

local function rank_shown_ids(shown)
  return M.sort_ids_by_priority(shown, function(id)
    return M.layout_priority(find(id))
  end)
end

--- Prefer a busy slot as the left master; keep focus primary if it is busy.
---@param ranked integer[]
---@param preferred integer|nil
---@return integer|nil
local function pick_layout_primary(ranked, preferred)
  if #ranked == 0 then
    return nil
  end
  if preferred then
    local s = find(preferred)
    if s and not s.parked and slot_busy(s) then
      return preferred
    end
  end
  for _, id in ipairs(ranked) do
    local s = find(id)
    if s and slot_busy(s) then
      return id
    end
  end
  -- Prefer contentful over empty idle for the large pane
  for _, id in ipairs(ranked) do
    local s = find(id)
    if s and slot_has_content(s) then
      return id
    end
  end
  if preferred then
    local s = find(preferred)
    if s and not s.parked then
      return preferred
    end
  end
  return ranked[1]
end

local function close_slot_win(slot)
  if slot.win and vim.api.nvim_win_is_valid(slot.win) then
    pcall(vim.api.nvim_win_close, slot.win, true)
  end
  slot.win = nil
end

--- Busy slots always unpark and show.
local function unpark_if_busy(slot)
  if slot and slot_busy(slot) and slot.parked then
    slot.parked = false
    if visible then
      M.apply_layout()
    end
  end
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

local resize_autocmd ---@type integer|nil
local function ensure_resize_autocmd()
  if resize_autocmd then
    return
  end
  resize_autocmd = vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      if visible and #slots > 1 then
        M.apply_layout()
      end
    end,
  })
end

--- Float border array. With gap=1, neighbors share one screen row/col; the
--- southern window owns that row (its titled top). Northern windows omit the
--- bottom so they don't paint over the title below.
---@param slot PiSlot
---@param focused boolean
---@param nbr { N?: boolean, S?: boolean, E?: boolean, W?: boolean }|nil
---@return table
function M.border_for(slot, focused, nbr)
  local hl = border_hl_name(slot.id, focused)
  nbr = nbr or {}
  local function cell(ch)
    return { ch, hl }
  end
  -- Shared edges use tee/junction chars so overlapping borders don't show ┐┌ seams.
  local tl, tr, bl, br
  if nbr.W and nbr.N then
    tl = "┼"
  elseif nbr.W then
    tl = "┬"
  elseif nbr.N then
    tl = "├"
  else
    tl = "┌"
  end
  if nbr.E and nbr.N then
    tr = "┼"
  elseif nbr.E then
    tr = "┬"
  elseif nbr.N then
    tr = "┤"
  else
    tr = "┐"
  end
  -- Neighbor below owns the shared row for its title — omit our bottom entirely.
  if nbr.S then
    return {
      cell(tl),
      cell("─"),
      cell(tr),
      cell("│"),
      cell(""), -- br
      cell(""), -- bottom
      cell(""), -- bl
      cell("│"),
    }
  end
  if nbr.W then
    bl = "┴"
  else
    bl = "└"
  end
  if nbr.E then
    br = "┴"
  else
    br = "┘"
  end
  return {
    cell(tl),
    cell("─"),
    cell(tr),
    cell("│"),
    cell(br),
    cell("─"),
    cell(bl),
    cell("│"),
  }
end

local function border_for(slot, focused, nbr)
  return M.border_for(slot, focused, nbr)
end

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

local function clip(s, n)
  s = tostring(s or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then
    return ""
  end
  if vim.fn.strdisplaywidth(s) > n then
    while #s > 0 and vim.fn.strdisplaywidth(s) > n - 1 do
      s = s:sub(1, -2)
    end
    return s .. "…"
  end
  return s
end

--- First non-empty line of user text → goal (layer 1).
local function goal_from_prompt(text)
  if type(text) ~= "string" then
    return nil
  end
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local t = line:gsub("^%s+", ""):gsub("%s+$", "")
    if t ~= "" and not t:match("^@") then
      return clip(t, 48)
    end
  end
  return clip(text, 48)
end

local function activity_from_tool(name, args)
  name = tostring(name or "tool")
  local detail = ""
  if type(args) == "table" then
    detail = args.command
      or args.cmd
      or args.path
      or args.file_path
      or args.filePath
      or args.pattern
      or args.query
      or args.url
      or args.prompt
      or ""
    if detail == "" and args.arguments and type(args.arguments) == "table" then
      local a = args.arguments
      detail = a.command or a.path or a.file_path or a.pattern or a.query or ""
    end
  elseif type(args) == "string" then
    detail = args
  end
  detail = clip(tostring(detail), 36)
  if detail ~= "" then
    return name .. ": " .. detail
  end
  return name
end

--- Update slot.activity from an RPC event (layer 2).
local function apply_activity(slot, ev)
  if not ev or not ev.type then
    return
  end
  if ev.type == "tool_execution_start" then
    slot.activity = activity_from_tool(ev.toolName, ev.args or ev.input or ev.toolArguments)
  elseif ev.type == "tool_execution_end" then
    local name = ev.toolName or (slot.activity and slot.activity:match("^([^:]+)")) or "tool"
    if ev.isError then
      slot.activity = tostring(name) .. " ✗"
    else
      slot.activity = tostring(name) .. " ✓"
    end
  elseif ev.type == "agent_start" or ev.type == "turn_start" then
    if not slot.activity or slot.activity == "" or slot.activity:match("✓$") or slot.activity:match("✗$") then
      slot.activity = "thinking"
    end
  elseif ev.type == "message_update" then
    if not slot.activity or slot.activity == "thinking" or slot.activity:match("✓$") then
      slot.activity = "replying"
    end
  elseif ev.type == "compaction_start" then
    slot.activity = "compacting"
  elseif ev.type == "agent_end" or ev.type == "agent_settled" or ev.type == "compaction_end" then
    slot.activity = nil
  end
end

--- Two-layer float title: `#id · goal · activity`.
--- Layer 1 = user goal (or session name); layer 2 = what it's doing now.
---@param slot PiSlot
---@param max_w integer|nil
function M.format_title(slot, max_w)
  local busy = slot.status == "busy" or slot.status == "streaming"
  local dot = busy and "●" or "○"
  local parts = { string.format("%s #%d", dot, slot.id) }
  local goal = slot.goal
  if not goal or goal == "" then
    goal = session_label(slot)
  end
  if goal and goal ~= "" then
    parts[#parts + 1] = goal
  end
  local act = slot.activity
  if (not act or act == "") and busy then
    act = "Working"
  end
  if act and act ~= "" then
    parts[#parts + 1] = act
  end
  if slot.id == primary_id then
    parts[#parts + 1] = "focus"
  end
  local title = " " .. table.concat(parts, " · ") .. " "
  max_w = max_w or (slot.win and vim.api.nvim_win_is_valid(slot.win) and vim.api.nvim_win_get_width(slot.win)) or 60
  max_w = math.max(20, max_w - 2)
  if vim.fn.strdisplaywidth(title) > max_w then
    -- Prefer keeping id + activity; shrink goal first
    if goal and #parts >= 3 then
      local budget = max_w - vim.fn.strdisplaywidth(string.format(" %s #%d ·  · %s ", dot, slot.id, act or ""))
      budget = math.max(8, budget)
      parts[2] = clip(goal, budget)
      title = " " .. table.concat(parts, " · ") .. " "
    end
    if vim.fn.strdisplaywidth(title) > max_w then
      title = clip(title, max_w)
      if not title:match(" $") then
        title = title .. " "
      end
    end
  end
  return title
end

local function title_for(slot)
  return M.format_title(slot)
end

local function refresh_slot_title(slot)
  if slot.win and vim.api.nvim_win_is_valid(slot.win) then
    local focused = slot.id == primary_id
    pcall(vim.api.nvim_win_set_config, slot.win, {
      title = title_for(slot),
      title_pos = "center",
      border = border_for(slot, focused, slot._nbr),
    })
  end
end

--- Re-apply ○ #N titles on every visible slot (used when ui.refresh_title would
--- otherwise stomp them with the singleton "pi chat" title).
function M.refresh_titles()
  for _, slot in ipairs(slots) do
    if not slot.parked then
      refresh_slot_title(slot)
    end
  end
end

--- Record user objective on the active (primary) slot.
function M.note_goal(text, id)
  local slot = id and find(id) or M.primary()
  if not slot then
    return
  end
  local g = goal_from_prompt(text)
  if g and g ~= "" then
    slot.goal = g
    refresh_slot_title(slot)
  end
end

--- Primary client events (same activity rules as satellites).
function M.on_primary_event(ev)
  local p = M.primary()
  if not p then
    return
  end
  apply_activity(p, ev)
  if ev.type == "agent_start" or ev.type == "turn_start" or ev.type == "message_update" or ev.type == "tool_execution_start" then
    if p.status ~= "busy" then
      p.status = "busy"
    end
  elseif ev.type == "agent_end" or ev.type == "agent_settled" then
    p.status = "idle"
  end
  unpark_if_busy(p)
  refresh_slot_title(p)
end

local function apply_slot_state(slot, data)
  if type(data) ~= "table" then
    return
  end
  if data.sessionName and data.sessionName ~= "" then
    slot.session_name = data.sessionName
    if not slot.goal or slot.goal == "" then
      slot.goal = clip(data.sessionName, 48)
    end
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
  local base = tonumber((require("pi.config").opts.window or {}).winblend) or 0
  -- Multi-slot must stay opaque: any winblend lets neo-tree/explorer bleed through.
  local blend = 0
  if base > 0 and #slots <= 1 then
    blend = focused and math.max(0, base - 6) or math.min(40, base + 12)
  end
  pcall(function()
    vim.wo[win].winblend = blend
  end)
  local border_hl = border_hl_name(slot.id, focused)
  pcall(function()
    vim.wo[win].winhl = "Normal:PiChatNormal,NormalFloat:PiChatNormal,EndOfBuffer:PiChatNormal,FloatBorder:"
      .. border_hl
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
  elseif ev.type == "message_update" or ev.type == "tool_execution_start" or ev.type == "tool_execution_end" then
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
  apply_activity(slot, ev)
  unpark_if_busy(slot)
  pcall(function()
    require("pi.render").on_event(slot.chat_buf, ev)
  end)
  refresh_slot_title(slot)
  if prev ~= slot.status then
    pcall(function()
      require("pi.statusline").repaint()
    end)
    -- Re-tile so newly busy/idle slots move to top-left priority
    if visible then
      vim.schedule(function()
        if visible then
          M.apply_layout()
        end
      end)
    end
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

--- Make sure the primary slot's RPC job is alive (restart satellites if needed).
---@return table|nil client
function M.ensure_primary_job()
  local p = M.primary() or M.ensure_default()
  if not p then
    return nil
  end
  local client = p.is_default and default_client() or p.client
  if client.is_running() then
    return client
  end
  if p.is_default then
    -- Default job: runtime.ensure_started starts the singleton.
    return client
  end
  local ok, err = pcall(function()
    require("pi.runtime").start_job(client, {
      on_event = function(ev)
        satellite_on_event(p, ev)
      end,
    })
  end)
  if not ok then
    vim.notify("pi: failed to restart slot #" .. tostring(p.id) .. ": " .. tostring(err), vim.log.levels.ERROR)
    return nil
  end
  if p.id == primary_id then
    bind_primary(p)
  else
    bind_satellite(p)
  end
  pcall(function()
    client.send({ type = "get_state", id = "slot-restart-" .. tostring(p.id) })
  end)
  return client
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
    pcall(M.ensure_primary_job)
    return true
  end
  local old = M.primary()
  if old then
    bind_satellite(old)
  end
  primary_id = id
  bind_primary(slot)
  pcall(M.ensure_primary_job)
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

--- Promote slot `#n` (title id) to master. Unparks if hidden.
---@param n integer
---@return boolean
function M.focus_by_id(n)
  n = tonumber(n)
  if not n or n < 1 then
    return false
  end
  local slot = find(n)
  if not slot then
    vim.notify(string.format("pi: no slot #%d", n), vim.log.levels.WARN)
    return false
  end
  if slot.parked then
    slot.parked = false
  end
  if not visible then
    M.show()
  end
  return M.set_primary(n)
end

--- Interactive / count-based focus. Prefer `12<leader>w`, or `<leader>w` then digits.
---@return boolean
function M.focus_ask()
  local n = vim.v.count
  if n and n > 0 then
    return M.focus_by_id(n)
  end
  local digits = ""
  local function echo()
    vim.api.nvim_echo({ { "pi → slot #" .. digits .. (digits == "" and "_" or ""), "Question" } }, false, {})
  end
  echo()
  -- First digit: blocking
  local c = vim.fn.getcharstr()
  if c == "\x1b" or c == "" then
    vim.api.nvim_echo({}, false, {})
    return false
  end
  if c == "\r" or c == "\n" then
    vim.api.nvim_echo({}, false, {})
    return false
  end
  if not c:match("^%d$") then
    vim.api.nvim_echo({}, false, {})
    vim.notify("pi: expected slot number", vim.log.levels.WARN)
    return false
  end
  digits = c
  echo()
  -- More digits (up to 3) with short timeout so `w` `1` `2` works for #12
  local max_digits = 3
  while #digits < max_digits do
    local got = nil
    local deadline = vim.uv.hrtime() + 600 * 1000000 -- 600ms
    while vim.uv.hrtime() < deadline do
      local code = vim.fn.getchar(0)
      if code ~= 0 and code ~= nil then
        got = type(code) == "number" and vim.fn.nr2char(code) or tostring(code)
        break
      end
      vim.wait(20, function()
        return false
      end, 20, false)
    end
    if not got then
      break
    end
    if got == "\x1b" then
      vim.api.nvim_echo({}, false, {})
      return false
    end
    if got == "\r" or got == "\n" or got == " " then
      break
    end
    if not got:match("^%d$") then
      break
    end
    digits = digits .. got
    echo()
  end
  vim.api.nvim_echo({}, false, {})
  local id = tonumber(digits)
  if not id then
    return false
  end
  return M.focus_by_id(id)
end

function M.apply_layout()
  if #slots == 0 then
    return
  end
  pcall(function()
    require("pi.ui").ensure_backdrop()
  end)
  ensure_slot_hl()
  ensure_slot_hl_autocmd()
  ensure_resize_autocmd()
  -- Close parked floats first
  for _, slot in ipairs(slots) do
    if slot.parked then
      close_slot_win(slot)
    end
  end
  local shown = layout_ids()
  if #shown == 0 then
    return
  end
  -- Busy / contentful slots → left master + top of the satellite stack
  local ranked = rank_shown_ids(shown)
  local layout_primary = pick_layout_primary(ranked, primary_id)
  if not layout_primary then
    return
  end
  -- Sync focus when master should follow a running agent
  if layout_primary ~= primary_id then
    local cur = primary_id and find(primary_id) or nil
    local want = find(layout_primary)
    if want and slot_busy(want) and (not cur or not slot_busy(cur)) then
      M.set_primary(layout_primary)
      return
    end
  end
  local ordered = { layout_primary }
  for _, id in ipairs(ranked) do
    if id ~= layout_primary then
      ordered[#ordered + 1] = id
    end
  end
  local layout = M.compute_layout({
    cols = vim.o.columns,
    lines = vim.o.lines,
    chrome = chrome_rows(),
    ids = ordered,
    primary = layout_primary,
  })
  local ui = require("pi.ui")
  for _, slot in ipairs(slots) do
    if not slot.parked then
      local g = layout[slot.id]
      if g then
        local focused = slot.id == primary_id or slot.id == layout_primary
        slot._nbr = g.nbr
        local cfg = {
          relative = "editor",
          width = g.width,
          height = g.height,
          row = g.row,
          col = g.col,
          style = "minimal",
          border = border_for(slot, focused, g.nbr),
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
  end
  pcall(function()
    require("pi.statusline").repaint()
  end)
end

--- Hide or re-show every idle (not working) slot window. Busy slots stay.
--- Toggle: idle visible → park them; idle parked → restore.
---@return string "hidden"|"shown"|"noop"
function M.toggle_idle()
  M.ensure_default()
  if not visible then
    M.show()
  end
  local idle = {}
  local busy_n = 0
  for _, s in ipairs(slots) do
    if slot_busy(s) then
      busy_n = busy_n + 1
      s.parked = false
    else
      idle[#idle + 1] = s
    end
  end
  if #idle == 0 then
    vim.notify("pi: no idle slots", vim.log.levels.INFO)
    return "noop"
  end
  local any_shown = false
  for _, s in ipairs(idle) do
    if not s.parked then
      any_shown = true
      break
    end
  end
  if any_shown then
    for _, s in ipairs(idle) do
      -- Keep at least one float if nothing is busy
      if busy_n == 0 and s.id == primary_id then
        s.parked = false
      else
        s.parked = true
        close_slot_win(s)
      end
    end
    local p = M.primary()
    if p and p.parked then
      for _, s in ipairs(slots) do
        if not s.parked then
          M.set_primary(s.id)
          break
        end
      end
    end
    M.apply_layout()
    local n = 0
    for _, s in ipairs(idle) do
      if s.parked then
        n = n + 1
      end
    end
    vim.notify(string.format("pi: hid %d idle slot(s)", n), vim.log.levels.INFO)
    return "hidden"
  end
  for _, s in ipairs(idle) do
    s.parked = false
  end
  M.apply_layout()
  vim.notify(string.format("pi: showed %d idle slot(s)", #idle), vim.log.levels.INFO)
  return "shown"
end

function M.show()
  M.ensure_default()
  require("pi.runtime").ensure_started()
  local p = M.primary()
  if p then
    bind_primary(p)
    require("pi.ui").adopt_chat_buf(p.chat_buf)
  end
  local ui = require("pi.ui")
  pcall(function()
    ui.conceal_explorer()
  end)
  pcall(function()
    ui.ensure_backdrop()
  end)
  -- ui.open paints primary buf; apply_layout applies per-slot colored borders
  ui.open()
  if p then
    p.win = ui.chat_win()
  end
  visible = true
  M.apply_layout()
end

function M.hide()
  -- Close every slot float, including the default slot (it may be a satellite
  -- after <leader>w{n} promoted another slot to master).
  for _, slot in ipairs(slots) do
    if slot.win and vim.api.nvim_win_is_valid(slot.win) then
      pcall(vim.api.nvim_win_close, slot.win, true)
    end
    slot.win = nil
  end
  local ui = require("pi.ui")
  ui.close()
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
