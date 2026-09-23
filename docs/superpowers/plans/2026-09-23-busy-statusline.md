# Busy statusline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a spinning `Working · Ns` in lualine while the pi agent is busy.

**Architecture:** New `pi.statusline` module owns timer + text. `pi.session` starts/stops it from busy transitions. Host neovim config mounts the lualine component.

**Tech Stack:** Neovim Lua, uv timer, lualine component API.

## Global Constraints

- Reuse `pi.session` busy (`streaming` / `idle`); no second busy flag.
- Idle → `lualine()` returns `""`.
- Do not paint chat/ask busy chrome.
- Do not auto-mutate arbitrary statusline plugins; document + wire host lualine only.

---

### Task 1: `pi.statusline` module + unit test

**Files:**
- Create: `lua/pi/statusline.lua`
- Create: `tests/statusline_test.lua`

**Interfaces:**
- Produces: `start()`, `stop()`, `lualine()` → `string`, `text()` alias of `lualine()`

- [x] **Step 1: Write failing test** — idle empty; after `start()` contains `Working`; after `stop()` empty again
- [x] **Step 2: Implement `lua/pi/statusline.lua`**
- [x] **Step 3: `nvim -u NONE -l tests/statusline_test.lua` passes**

### Task 2: Hook session / abort

**Files:**
- Modify: `lua/pi/session.lua` (`on_event`, `apply_state`, `reset`)
- Modify: `lua/pi/runtime.lua` (`abort`)

- [x] **Step 1: start on streaming, stop on idle/reset/abort**
- [x] **Step 2: suite still green (`tests/run.lua`)**

### Task 3: Wire host lualine + README

**Files:**
- Modify: `/Users/meetai/.config/nvim/lua/plugins/statusline.lua`
- Modify: `README.md` (one line under suggested keys / UI)

- [x] **Step 1: prepend pi busy component to `lualine_x` with `cond`**
- [x] **Step 2: mention in README**
