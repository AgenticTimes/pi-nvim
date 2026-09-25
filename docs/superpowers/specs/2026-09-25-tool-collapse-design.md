# Tool output collapse

Date: 2026-09-25  
Status: approved

## Goal

Long toolcall boxes no longer dominate the chat. Default view is compact; user can expand in place.

## Behavior

- Default: header (`⚙ name ✓`) + up to **3** body lines (errors: **6**).
- If truncated: last line `  … +N lines  za expand`.
- Cursor inside that tool box: `<CR>` or `za` toggles full ↔ collapsed.
- `<CR>` outside a collapsible tool box: still opens ask popup.
- Identical consecutive calls still collapse to `×N` (unchanged).

## Implementation sketch

- `tool_block` builds a **full** line list (higher cap ~80).
- Store `tool_full` / `tool_expanded` on the tool bubble.
- Buffer shows collapsed or full; toggle rewrites that range and shifts later bubbles.
- Export `M.toggle_tool_at_cursor(buf, win)`.

## Out of scope

- Neovim `foldmethod`
- Thinking / assistant box collapse
- Review pending badge (next iteration)
