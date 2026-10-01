# Slot maximize (solo) — design

**Date:** 2026-10-01  
**Status:** approved (pending user review of this file)  
**Related:** `2026-09-26-multi-slot-agent-ui-design.md`

## Goal

In multi-slot mode, temporarily show **one** slot full-bleed over the pi UI area, then restore the tiled multi-slot layout without stopping jobs.

## Keymap

| Input | Action |
|-------|--------|
| `N<leader>m` or `<leader>m` then digits | Maximize slot `#N` |
| `<leader>m` alone (no count / no digits) while maximized | Restore multi-slot layout |
| Esc / empty Enter during digit entry | Cancel; layout unchanged |

Config: `keys.slot_maximize = "<leader>m"` (empty string disables plugin default binding). Host configs (e.g. nvim `keymaps/pi.lua`) may mirror the map.

Does **not** replace:

- `<leader>w` — promote slot to left master; satellites stay visible
- `<leader>aF` / `:PiFullscreen` — single-float chrome; ignored for geometry when multi-slot owns layout

## Behavior

1. **State:** `slots` keeps `maximized_id: integer|nil`.
2. **Enter maximize `#N`:**
   - Resolve slot (unpark if needed); show UI if hidden.
   - Set `maximized_id = N`; `set_primary(N)` so ask / interrupt target that agent.
   - `apply_layout`: only `#N` gets a float sized like the full multi-slot outer rect (same margins/chrome as today's master area when alone); close other slot wins (buffers + RPC jobs stay alive).
   - Title hint: e.g. `○ #7 ✦` (or `●` when busy).
3. **Restore (`<leader>m` with no number while `maximized_id` set):**
   - Clear `maximized_id`; `apply_layout` tiles all non-parked slots again.
   - Keep current primary (the maximized slot stays primary unless user later cycles).
4. **Edge cases:**
   - Unknown `#N` → warn, noop.
   - Already maximized `#N` and user maximizes `#M` → switch solo to `#M` (don't require restore first).
   - Already maximized `#N` and user maximizes `#N` again via digits → treat as restore (optional symmetry) **or** noop; prefer **restore** so `m` `7` twice is safe.
   - Single visible slot + `<leader>m` with no digits → noop / info (nothing to restore).
   - Close maximized slot → clear `maximized_id`, re-layout remaining.
   - `toggle_idle` / create / close / resize → respect `maximized_id` (still solo until restore).
5. **Viewer slots:** maximize allowed (look-only); primary RPC stays on a non-viewer if current primary would become invalid — same rules as `set_primary` for viewers when focusing for view-only is insufficient; maximizing a viewer focuses its win but does not steal RPC primary (mirror existing viewer focus behavior).

## API

```lua
require("pi.slots").maximize_by_id(n)  -- enter solo #n
require("pi.slots").maximize_restore() -- clear solo
require("pi.slots").maximize_ask()     -- count / digits / bare toggle restore
require("pi.slots").maximized_id()     -- integer|nil
```

Commands (optional): `:PiMaximize [N]` — with N maximize; without N restore if maximized else prompt digits.

## Tests

- Unit: `maximized_id` set → `compute_layout` / apply path yields one geometry; restore yields multi ids again.
- Digit / count path mirrors `focus_ask` (reuse helper if cheap).
- Close while maximized clears state.

## Out of scope

- Animations; per-slot remembered tile sizes.
- Maximizing non-pi editor windows.
