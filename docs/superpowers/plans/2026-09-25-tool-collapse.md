# Tool output collapse Implementation Plan

> **For agentic workers:** implement task-by-task. Steps use checkbox syntax.

**Goal:** Collapsible toolcall boxes in chat (3/6 body lines default; `za`/`<CR>` expand).

**Architecture:** Build full tool lines once, store on the tool bubble, paint collapsed by default; toggle rewrites the box range and shifts later bubbles.

**Tech Stack:** Neovim Lua, existing `render.lua` / `ui.lua` keymaps, headless tests.

## Global Constraints

- Do not break ×N consecutive-tool collapse.
- Chat `<CR>` must still open ask when not on a collapsible tool.
- No new runtime dependencies.

---

### Task 1: Collapse helpers + tool_block full/collapsed

**Files:** `lua/pi/render.lua`, `tests/render_test.lua`

- [ ] Add `collapse_tool_lines(full, expanded, has_err)` 
- [ ] `tool_block` returns full lines (cap ~80); callers apply collapse
- [ ] Store `tool_full` / `tool_expanded` on bubble via `note_tool_lines` / upsert
- [ ] Test: long args → marker line; short → no marker

### Task 2: Toggle + keymaps

**Files:** `lua/pi/render.lua`, `lua/pi/ui.lua`

- [ ] `M.toggle_tool_at_cursor(buf, win)` find tool bubble, swap lines, shift bubbles, repaint
- [ ] Chat `<CR>`: toggle if handled, else `open_input`
- [ ] Chat `za`: toggle
- [ ] Test: expand then collapse restores marker

### Task 3: Docs + suite

- [ ] README one-liner under chat keys
- [ ] `nvim -u NONE -l tests/run.lua` green
