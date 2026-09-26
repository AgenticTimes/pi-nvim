# Multi-slot Agent UI (master + satellites)

**Date:** 2026-09-26  
**Hotkey:** `<C-Space>` summon / hide  
**Default layout:** one large **primary** float; other slots as smaller **satellites** around it (split-like).  
**Backends:** pi first; interface ready for more agents later.

## Concepts

| Term | Meaning |
|------|---------|
| Backend | Adapter: start/stop/prompt/abort/events (`pi` now) |
| Slot | One backend instance + session + chat UI surface |
| Primary | Focused slot — large translucent float |
| Satellite | Other running/idle slots — smaller floats around primary |

## Layout (target)

```
┌─────────────────────────────┬──────────┐
│                             │ ○ #2     │
│   ● #1 · focus              ├──────────┤
│   (enlarged / blue border)  │ ○ #3     │
│                             ├──────────┤
│                             │ ○ #4     │
└─────────────────────────────┴──────────┘
```

- Focused slot = master (≈66% width, full height, blue border, title `· focus`).
- Others stack on the right; click / Enter promotes → that slot enlarges.
- `<C-Space>`: if any slot UI hidden → show layout; if shown → hide all (jobs keep running).

## Phases

### M1 (this iteration) — single slot, product shell
- Bootstrap agent in background on Neovim start (no UI).
- When RPC ready → notify `pi ready · <C-Space>`.
- `<C-Space>` toggles one **fullscreen translucent** float (primary only).
- Jobs survive hide; interrupt/compact still work.

### M2 — multi-slot parallel ✅
- N pi jobs (`pi.client.new`); `pi.slots` create/close/cycle; primary + satellites layout.
- `<C-Space>` → `slots.toggle_visible()`; `<leader>a+` / `a_` / `a>` new/close/cycle.
- **Any slot window is interactive:** click / `<CR>` promotes that slot to primary and opens ask; prompt/abort target the focused slot.

### M3 — multi-backend
- Stable Backend interface; second agent adapter.

## M1 config sketch

```lua
require("pi").setup({
  bootstrap = true,          -- VimEnter ensure_started, no UI
  summon_key = "<C-Space>",  -- toggle float
  window = {
    layout = "float",        -- translucent overlay (not side split)
    width = 1.0,
    height = 1.0,
    border = "rounded",
    winblend = 15,
  },
})
```

## Out of scope for M1
- Multiple concurrent slots / satellites
- Non-pi backends
- Changing `<Leader>ai` semantics beyond also toggling the same float
