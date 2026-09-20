# Tool-batch box

> Colors superseded by `2026-09-20-three-role-boxes-design.md`: tool batches keep
> their own violet square box instead of sharing the user bubble chrome.

## Goal

Consecutive tool calls share one box (bar + unicode border + light bg). Each call is a
block: header `⚙ name ✓|✗|… ×N` plus one indented line per argument, `$ command` for
bash, `! …` lines for errors.

## Behavior

- Stream: each new tool block joins the current box when contiguous; a rewritten block
  (collapse ×N) repaints in place; assistant/thinking/user text closes the box.
- Hydrate: each historical `toolCall` part renders the same block from its `arguments`;
  a bare count is the fallback.
- Resize: repaint all remembered bubble ranges.
- Jump: `[[`/`]]` match `^⚙` and any box start.

## Out of scope

Bullet-list tool UI (`● path`).
