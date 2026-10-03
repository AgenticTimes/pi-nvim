# Diff Preview (Ctrl+R / Ctrl+O) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Preview-only diffs; no auto accept/reject gate. Edits apply immediately; `<C-r>` / `<C-o>` open BEFORE/AFTER.

**Architecture:** `review.open` becomes preview-mode by default (nav + q only). `auto_show` is a no-op. Chat keys + hint point at preview. `:PiAccept`/`:PiReject` stay as commands. On `agent_end`, optional silent write of touched buffers.

**Tech Stack:** Neovim Lua, existing `pi.review` / `pi.session.touched` / `pi.render.note_pending_review`

---

### Task 1: Config + review preview API

**Files:**
- Modify: `lua/pi/config.lua`
- Modify: `lua/pi/review.lua`
- Modify: `lua/pi/runtime.lua` (auto_show call site stays; behavior changes)
- Modify: `plugin/pi.lua` (`PiDiff` → preview)

**Steps:**
1. Add `keys.preview = "<C-r>"`, `keys.preview_all = "<C-o>"`
2. `auto_show()` → no-op
3. `open(idx, opts)` preview mode: map only `]f`/`[f`/`]h`/`[h`/`q`; hint/winbar/list text without a/r
4. `preview()` → last touched (no list); `preview_all()` → list + first; `write_pending()` for silent disk flush
5. Keep `accept`/`reject`/`*_all`/`*_hunk` for commands

### Task 2: Chat UX

**Files:**
- Modify: `lua/pi/ui.lua` — bind preview keys on chat
- Modify: `lua/pi/render.lua` — hint text + call `write_pending` from `note_pending_review`
- Modify: `lua/pi/init.lua` — export `preview` / `preview_all` if useful

### Task 3: Tests

**Files:**
- Modify: `tests/hunk_test.lua`, `tests/render_test.lua`, `tests/smoke_test.lua`
- Create: `tests/preview_test.lua`

**Verify:** `nvim --headless -u NONE -c "luafile tests/run.lua"` (or project’s usual runner) for affected tests.
