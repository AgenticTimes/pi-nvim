# User bubble box Implementation Plan

> **For agentic workers:** Execute task-by-task.

**Goal:** Draw a unicode box + light background around user turns in chat.

**Architecture:** Extmark painting in `pi.render` after `append_user`; colors in `pi.ui.ensure_hl`; resize redraw.

**Tech Stack:** Neovim Lua extmarks (`virt_text`, `virt_lines`, `line_hl_group`, signs)

## Global Constraints

- Do not mutate user buffer text with box characters
- Keep `jump_message` working via you-bar signs
- Thinking / tool get their own distinct boxes (see `2026-09-20-three-role-boxes-design.md`)

---

### Task 1: Highlights + paint_user_bubble

**Files:** `lua/pi/ui.lua`, `lua/pi/render.lua`, `tests/hydrate_test.lua`

- [x] Add `PiYouBubble` / `PiYouBorder`
- [x] Paint box+bg+bar on user ranges; track ranges; repaint on resize
- [x] Test asserts bar + bubble/border marks; run `nvim -u NONE -l tests/run.lua`
