# Review return-to-chat Implementation Plan

**Goal:** `A`/`R` accept/reject all on diff page; empty queue returns to pi chat.

## Task 1: Keys + copy

- [x] Map `A` → accept_all, `R` → reject_all in review buffers
- [x] Update virt_line hint, pending list help, winbar, README

## Task 2: finish_empty → chat

- [x] Close review chrome, `ui.open` + `focus_chat`
- [x] Notify: busy → waiting; idle → review done; open-empty → no pending
- [x] Rely on existing `auto_show` for new diffs while busy

## Task 3: Tests

- [x] review / review_all / hunk assert chat open after empty; close ui to avoid suite pollution
- [x] Suite green
