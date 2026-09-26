# Compact support design

**Date:** 2026-09-26  
**Scope:** pi.nvim RPC compact + auto-compaction + UI events

## API

- `pi.compact({ custom_instructions? })` → `{ type = "compact", customInstructions? }`
- `pi.set_auto_compaction(bool)` / `pi.toggle_auto_compaction()`
- `:PiCompact [instructions…]`, `:PiAutoCompact`

## UI

- `compaction_start` → session `compacting` + statusline `Compacting · Ns`
- `compaction_end` → idle; chat line `· compacted {before} → {after}` or warn on fail/abort
- Responses notify success/failure

## Keys (host nvim)

- `SPC a C` → compact (no prompt)
- Instructions via `:PiCompact …` only

## Out of scope

- Slash `/compact` (pi builtin)
- Full history re-hydrate after compact
