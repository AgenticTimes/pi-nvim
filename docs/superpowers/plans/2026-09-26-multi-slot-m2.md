# Multi-slot M2 Implementation Plan

> **For agentic workers:** Implement task-by-task. Steps use checkbox syntax.

**Goal:** Multiple parallel pi RPC slots with primary + satellite translucent floats; `<C-Space>` shows/hides the whole layout.

**Architecture:** Factory `pi.client.new()` for per-slot jobs. `pi.slots` owns slot list + primary id + layout. Primary gets full runtime/tools; satellites stream+render only. Input/prompt/abort target primary.

**Tech Stack:** Neovim Lua, existing pi.ui/render/runtime.

## Global Constraints

- Keep singleton `pi.client` API working (default slot).
- Max 4 slots (1 primary + 3 satellites) by default.
- Hide keeps all jobs running.
- M3 backends deferred — slots hardcode pi for now.

---

### Task 1: Client factory

**Files:** Modify `lua/pi/client.lua`; Test: `tests/client_multi_test.lua`

- [x] `Client.new()` with isolated job/acc/pending
- [x] Module API delegates to default instance

### Task 2: slots manager + layout

**Files:** Create `lua/pi/slots.lua`; Modify `lua/pi/ui.lua` or layout in slots

- [x] create/close/set_primary/list
- [x] geometry: satellites top row, primary bottom
- [x] show/hide all floats

### Task 3: Wire bootstrap, summon, keys

**Files:** `init.lua`, `runtime.lua`, `config.lua`, host keymaps

- [x] bootstrap creates slot 1
- [x] `<C-Space>` → slots.toggle_visible()
- [x] new/close/cycle primary keymaps

### Task 4: Tests + docs

- [x] layout test with 2 fake slots
- [x] update design doc M2 status
- [x] README + commit/push
