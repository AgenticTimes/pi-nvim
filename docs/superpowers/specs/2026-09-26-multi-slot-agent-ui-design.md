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
┌──────── satellite ─┐┌──── satellite ────┐
│ slot B (mini)      ││ slot C (mini)     │
└────────────────────┘└───────────────────┘
┌─────────────────────────────────────────┐
│                                         │
│          PRIMARY (slot A)               │
│          translucent float              │
│                                         │
└─────────────────────────────────────────┘
```

- `<C-Space>`: if any slot UI hidden → show layout; if shown → hide all (jobs keep running).
- Focus primary for input; click/keymap to promote a satellite to primary.

## Phases

### M1 (this iteration) — single slot, product shell
- Bootstrap agent in background on Neovim start (no UI).
- When RPC ready → notify `pi ready · <C-Space>`.
- `<C-Space>` toggles one **fullscreen translucent** float (primary only).
- Jobs survive hide; interrupt/compact still work.

### M2 — multi-slot parallel
- N pi jobs; new/close slot; primary + satellites layout.
- Slot-local abort/prompt; status dots on satellites.

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
