# Diff preview (Ctrl+R / Ctrl+O) — no accept/reject gate

**Date:** 2026-10-03  
**Status:** approved (approach A)

## Goal

Replace the default Accept/Reject review gate with OpenCode-style preview:

- Edits apply to buffers immediately (already true for host tools).
- `<C-r>` previews the latest (or indexed) changed file as BEFORE/AFTER diff.
- `<C-o>` opens the pending-file list and previews all (cycle with `]f`/`[f`).
- `q` closes preview; no `a`/`r` required.
- `:PiAccept` / `:PiReject` remain for power users.

## Behavior

| Action | Result |
|--------|--------|
| Host edit | Record in `session.touched`; do **not** auto-open review UI |
| Agent end | If `write_on_accept`, silent-write touched buffers; keep `touched` for preview |
| Chat hint | `◎ N files · <C-r> preview · <C-o> all` |
| `<C-r>` | Open diff for last touched file (or `:PiDiff`) |
| `<C-o>` | Open pending list + first file |
| `q` | Close preview chrome; return focus to chat |
| `]f`/`[f` | Next/prev file while preview open |

## Non-goals

- No new reject/undo key in v1 (use `u` / git).
- No change to how host tools mutate buffers.
