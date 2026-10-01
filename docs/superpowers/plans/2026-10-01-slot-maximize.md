# Slot Maximize (Solo) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Multi-slot UI can solo one slot full-bleed via `<leader>m` + id, and restore the tile layout with bare `<leader>m`.

**Architecture:** Add module state `maximized_id` in `lua/pi/slots.lua`. `apply_layout` shows only that id when set (full usable rect via existing `compute_layout` with a single id). Digit entry reuses the same pattern as `focus_ask`. Wire config key, command, host keymap, README.

**Tech Stack:** Neovim Lua, existing `tests/helpers.lua` + `nvim -u NONE -l tests/...`

## Global Constraints

- Do not stop RPC jobs when hiding satellite floats during maximize.
- Viewer slots: maximize focuses their win; do not steal RPC primary (same as `set_primary` for viewers).
- `<leader>w` / `:PiFullscreen` behavior unchanged.
- Default key: `keys.slot_maximize = "<leader>m"`; empty string disables auto-bind.

## File map

| File | Role |
|------|------|
| `lua/pi/slots.lua` | `maximized_id`, maximize/restore/ask APIs, layout + title + close |
| `lua/pi/config.lua` | `keys.slot_maximize` |
| `lua/pi/init.lua` | setup keymap + `M.maximize_slot` |
| `plugin/pi.lua` | `:PiMaximize` |
| `tests/slots_maximize_test.lua` | state + layout + restore + close |
| `README.md` | document keys |
| `lua/core/keymaps/pi.lua` (nvim config repo, optional) | mirror `<Leader>m` if host overrides plugin keys |

---

### Task 1: Core maximize state + layout + tests

**Files:**
- Create: `tests/slots_maximize_test.lua`
- Modify: `lua/pi/slots.lua`

**Interfaces:**
- Produces:
  - `slots.maximized_id() -> integer|nil`
  - `slots.maximize_by_id(n) -> boolean`
  - `slots.maximize_restore() -> boolean` (true if cleared)
  - `slots.maximize_ask() -> boolean`
  - `_reset_for_test` also clears `maximized_id`

- [ ] **Step 1: Write failing test**

```lua
-- tests/slots_maximize_test.lua
local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.slots"] = nil
package.loaded["pi.config"] = nil
require("pi.config").setup({ bootstrap = false, max_slots = 64 })
local slots = require("pi.slots")
slots._reset_for_test()

-- Pure layout: solo one id fills like single-slot compute_layout
local solo = slots.compute_layout({
  cols = 100, lines = 40, chrome = 2, ids = { 7 }, primary = 7, margin = 1, min_w = 24, min_h = 6,
})
h.assert_truthy(solo[7], "solo geo for #7")
h.assert_eq(solo[7].row, 1, "row")
h.assert_eq(solo[7].col, 1, "col")
h.assert_falsy(solo[1], "no other ids")

-- API present
h.assert_eq(slots.maximized_id(), nil, "initially nil")

-- maximize_by_id / restore without needing real floats: stub ensure path via state
-- Create two logical slots through ensure_default + create (may open wins — ok in headless)
local d = slots.ensure_default()
h.assert_truthy(d, "default")
local s2 = assert(slots.create())
local id2 = s2.id

h.assert_truthy(slots.maximize_by_id(id2), "maximize ok")
h.assert_eq(slots.maximized_id(), id2, "maximized_id set")
-- primary should be id2 (non-viewer)
h.assert_eq(slots.primary().id, id2, "primary follows maximize")

h.assert_truthy(slots.maximize_restore(), "restore")
h.assert_eq(slots.maximized_id(), nil, "cleared")

-- maximize same id again via by_id while maximized → restore (spec)
h.assert_truthy(slots.maximize_by_id(id2), "max again")
h.assert_truthy(slots.maximize_by_id(id2), "same id restores")
h.assert_eq(slots.maximized_id(), nil, "restored by same id")

-- unknown id
h.assert_false(slots.maximize_by_id(9999), "missing")

-- close while maximized clears
h.assert_truthy(slots.maximize_by_id(id2), "max for close")
slots.close(id2)
h.assert_eq(slots.maximized_id(), nil, "cleared on close")

print("OK slots_maximize_test")
```

- [ ] **Step 2: Run test — expect fail**

```bash
cd ~/source/pi.nvim && nvim -u NONE -l tests/slots_maximize_test.lua
```

Expected: error/assert on missing `maximize_by_id` / `maximized_id`.

- [ ] **Step 3: Implement in `lua/pi/slots.lua`**

Add near top with other locals:

```lua
local maximized_id ---@type integer|nil
```

Helpers / API (place near `focus_by_id` / `focus_ask`):

```lua
function M.maximized_id()
  return maximized_id
end

function M.maximize_restore()
  if not maximized_id then
    return false
  end
  maximized_id = nil
  if visible or require("pi.ui").is_open() then
    M.apply_layout()
  end
  return true
end

---@param n integer
---@return boolean
function M.maximize_by_id(n)
  n = tonumber(n)
  if not n or n < 1 then
    return false
  end
  if maximized_id == n then
    return M.maximize_restore()
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
  maximized_id = n
  if slot.is_viewer then
    -- look-only: focus win, keep RPC primary
    if slot.win and vim.api.nvim_win_is_valid(slot.win) then
      pcall(vim.api.nvim_set_current_win, slot.win)
    end
  else
    M.set_primary(n)
  end
  M.apply_layout()
  return true
end

--- Count / digits / bare restore. Mirror focus_ask digit loop.
function M.maximize_ask()
  local n = vim.v.count
  if n and n > 0 then
    return M.maximize_by_id(n)
  end
  -- If already maximized and user hits bare mapping with no pending digits,
  -- getchar path below: first key Esc/Enter → restore when maximized.
  local digits = ""
  local function echo()
    local hint = maximized_id and (" [solo #" .. maximized_id .. "; Enter=restore]") or ""
    vim.api.nvim_echo({ { "pi → maximize #" .. digits .. (digits == "" and "_" or "") .. hint, "Question" } }, false, {})
  end
  echo()
  local c = vim.fn.getcharstr()
  if c == "\x1b" then
    vim.api.nvim_echo({}, false, {})
    return false
  end
  if c == "\r" or c == "\n" or c == "" then
    vim.api.nvim_echo({}, false, {})
    if maximized_id then
      return M.maximize_restore()
    end
    return false
  end
  if not c:match("^%d$") then
    vim.api.nvim_echo({}, false, {})
    -- Bare non-digit while maximized: treat as restore for toggle UX
    -- Actually keymap calls maximize_ask with no char — digit entry always.
    -- Spec: bare <leader>m = restore. That means maximize_ask must restore
    -- BEFORE waiting for getchar when we want true toggle-on-second-press.
    vim.notify("pi: expected slot number", vim.log.levels.WARN)
    return false
  end
  -- ... same 600ms multi-digit loop as focus_ask ...
  -- then return M.maximize_by_id(tonumber(digits))
end
```

**Important UX fix for bare `<leader>m`:** `maximize_ask` must **not** block on getchar when the intent is toggle-restore. Preferred behavior:

```lua
function M.maximize_ask()
  local n = vim.v.count
  if n and n > 0 then
    return M.maximize_by_id(n)
  end
  -- Peek one char with short timeout? Spec says bare m restores.
  -- Implementation: wait for first char; if timeout with no input → restore if maximized.
  -- Simpler approach matching user confirmation:
  --   1) if maximized_id and no count → restore immediately (no digit prompt)
  --   2) else prompt digits like focus_ask
  if maximized_id then
    return M.maximize_restore()
  end
  -- digit prompt identical to focus_ask, then maximize_by_id
end
```

This matches approved UX: second `<leader>m` restores without typing.

Patch `apply_layout` after `local shown = layout_ids()`:

```lua
  if maximized_id then
    local keep = false
    for _, id in ipairs(shown) do
      if id == maximized_id then
        keep = true
        break
      end
    end
    if keep then
      shown = { maximized_id }
    else
      maximized_id = nil
    end
  end
```

When building floats, close wins for slots not in `shown` / layout (already parked path closes; also close satellites not in solo set):

```lua
  for _, slot in ipairs(slots) do
    if maximized_id and slot.id ~= maximized_id then
      close_slot_win(slot)
    end
  end
```

(Do this before opening the solo win.)

Patch `format_title`: after id part, if `maximized_id == slot.id` append `✦` to the first part or parts list:

```lua
  if maximized_id == slot.id then
    parts[1] = parts[1] .. " ✦"
  end
```

Patch `M.close`: if `maximized_id == id` then `maximized_id = nil` before re-layout.

Patch `_reset_for_test`: `maximized_id = nil`.

Extract shared digit reader optional — YAGNI: copy `focus_ask` loop into `maximize_ask` for Task 1; refactor only if trivial.

- [ ] **Step 4: Run tests**

```bash
cd ~/source/pi.nvim && nvim -u NONE -l tests/slots_maximize_test.lua
cd ~/source/pi.nvim && nvim -u NONE -l tests/slots_layout_test.lua
cd ~/source/pi.nvim && nvim -u NONE -l tests/slots_idle_toggle_test.lua
```

Expected: all print OK.

- [ ] **Step 5: Commit**

```bash
git add lua/pi/slots.lua tests/slots_maximize_test.lua
git commit -m "feat(slots): maximize/solo one slot and restore tile layout"
```

---

### Task 2: Config, command, public API, README, host keymap

**Files:**
- Modify: `lua/pi/config.lua` (`keys.slot_maximize = "<leader>m"`)
- Modify: `lua/pi/init.lua` (setup bind + `M.maximize_slot`)
- Modify: `plugin/pi.lua` (`:PiMaximize`)
- Modify: `README.md` (one sentence in multi-slot paragraph)
- Modify (nvim config): `lua/core/keymaps/pi.lua` — `<Leader>m` → `require("pi.slots").maximize_ask()`

**Interfaces:**
- Consumes: Task 1 APIs
- Produces: user-facing keys/commands

- [ ] **Step 1: Config + init**

In `config.lua` keys:

```lua
slot_maximize = "<leader>m",
```

In `init.lua` setup after `slot_focus`:

```lua
  if keys.slot_maximize and keys.slot_maximize ~= "" then
    vim.keymap.set("n", keys.slot_maximize, function()
      require("pi.slots").maximize_ask()
    end, { desc = "pi: maximize slot #N / restore tiles" })
  end
```

```lua
function M.maximize_slot(n)
  if n == nil or n == true then
    return require("pi.slots").maximize_ask()
  end
  return require("pi.slots").maximize_by_id(n)
end
```

- [ ] **Step 2: Command**

```lua
vim.api.nvim_create_user_command("PiMaximize", function(opts)
  local arg = opts.args
  if arg == "" then
    require("pi.slots").maximize_ask()
    return
  end
  local n = tonumber(arg)
  if not n then
    vim.notify("pi: usage :PiMaximize [id]", vim.log.levels.WARN)
    return
  end
  require("pi.slots").maximize_by_id(n)
end, { nargs = "?", desc = "Maximize slot #N, or restore if none / already solo" })
```

Note: with Task 1's `maximize_ask`, bare `:PiMaximize` while maximized restores; while tiled prompts digits (blocking). Prefer for command when no args and maximized → restore; when no args and not maximized → `maximize_ask` digit prompt. Already handled.

- [ ] **Step 3: README**

Add to multi-slot sentence: `` `<leader>m` then digits (or `7<leader>m`) maximize that slot; bare `<leader>m` restores tiles ``.

- [ ] **Step 4: Host keymap** (`~/.config/nvim/lua/core/keymaps/pi.lua`)

```lua
map("n", "<Leader>m", function()
  require("pi.slots").maximize_ask()
end, { desc = "pi: maximize slot #N / restore" })
```

- [ ] **Step 5: Manual smoke** (optional in agent: skip if no UI)

- [ ] **Step 6: Commit** (pi.nvim and nvim config separately if both dirty)

```bash
# pi.nvim
git add lua/pi/config.lua lua/pi/init.lua plugin/pi.lua README.md
git commit -m "feat(slots): bind <leader>m and :PiMaximize for slot solo"

# ~/.config/nvim if mapping added
git add lua/core/keymaps/pi.lua
git commit -m "feat(pi): <Leader>m maximizes slot / restores tiles"
```

---

## Spec coverage check

| Spec item | Task |
|-----------|------|
| `<leader>m` + digits / count | 1 + 2 |
| Bare `<leader>m` restore | 1 (`maximize_ask`) |
| Jobs keep running | 1 (close wins only) |
| Primary follows (non-viewer) | 1 |
| Title ✦ | 1 |
| Same id again = restore | 1 |
| Switch #N → #M | 1 (`maximize_by_id`) |
| Close clears | 1 |
| Viewer rules | 1 |
| Config / README / command | 2 |

## Placeholder scan

None intentional. Digit loop: copy from `focus_ask` rather than “similar to”.
