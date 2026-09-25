# Chat markdown isolation Implementation Plan

> **For agentic workers:** implement task-by-task.

**Goal:** Stop host markdown renderers from overlaying Pi chat boxes.

**Architecture:** Dedicated `pi-chat` filetype + Treesitter markdown language register.

## Task 1: Chat filetype

**Files:** `lua/pi/render.lua`

- [x] `filetype = "pi-chat"`
- [x] `pcall(vim.treesitter.language.register, "markdown", "pi-chat")`
- [x] Do not call `render-markdown.buf_disable` (wrong buffer / unnecessary)

## Task 2: Test + docs

- [x] Assert chat ft in `tests/render_test.lua`
- [x] README note
- [x] Spec: `docs/superpowers/specs/2026-09-25-chat-markdown-isolation-design.md`
- [x] Suite green + commit
