# Inline edit mini-diff in tool bubbles

**Date:** 2026-10-03  
**Status:** approved (approach A)

## Goal

For host-tool content edits, show a Cursor-style truncated diff inside the toolcall bubble, with `<C-r>` opening the existing full BEFORE/AFTER preview.

## Behavior

| Case | Collapsed tool body |
|------|---------------------|
| Host edit (`session.touched` match) | `path` + mini-diff (± hunk, ≤8 lines) + `<C-r> full diff` |
| Other tools (bash/read/…) | Keep header + first arg preview + fold marker |
| Error tools | Stay expanded (unchanged) |

## Data

- Source: latest `session.touched` entry whose `path`/`rel` matches the tool args (or the edit just recorded for this tool call).
- Diff: line-oriented vs `before` snapshot and current buffer lines.
- Show first hunk only; truncate with `… +N · <C-r> full diff`.

## Interaction

- Chat / tool focus: existing `<C-r>` → `review.preview` for that file when possible.
- Top-rule hint may include `<C-r> review` for edit tools.
- No accept/reject gate (already decided).

## Non-goals

- Multi-hunk gallery inside the bubble.
- Auto-open full diff on every edit.

## Follow-up

- Path-parse disk writes (bash `>`, `tee`, …): see `2026-10-03-file-write-diff-design.md`.
