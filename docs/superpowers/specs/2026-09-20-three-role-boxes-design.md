# Three role boxes (user / tool / thinking)

Supersedes the styling parts of `2026-09-20-user-bubble-box-design.md` and
`2026-09-20-tool-batch-box-design.md`.

## Goal

Every non-assistant role in the chat buffer is visibly enclosed in its own box,
so user input, tool calls and thinking are told apart at a glance.

| Role | Box | Left bar | Highlight groups |
| --- | --- | --- | --- |
| user | rounded, solid `╭─ user ─╮ │ ╰─╯` | `▌` | `PiYouBar` / `PiYouBorder` / `PiYouBubble` |
| toolcall | square, solid `┌─ toolcall ─┐ │ └─┘` | `▌` | `PiToolBar` / `PiToolBorder` / `PiToolBubble` |
| thinking | rounded, dashed `╭┄ thinking ┄╮ ┊ ╰┄╯` | `▏` | `PiThinkBar` / `PiThinkBorder` / `PiThinkBubble` |

Each top rule carries the role name in its left corner as its own virt_line chunk
(`label` / `label_hl` in `STYLES`), so it keeps the role color and the corner still
lands on the box edge.

Assistant text stays unboxed.

## Tool call bodies

A tool box is a block: header `⚙ name ✓|✗|… ×N`, then one indented line per argument
(`path: …`, `offset: 10`, …). `command` is rendered as a shell line (`$ …`) instead of
a key/value pair, and a failing call appends the result text as `! …` lines highlighted
red. Guard rails: `cap_lines` (12 arg lines), `MAX_ARG_CHARS` (2000 chars per value),
`cap_lines(lines, 24)` per block, and `wrap_line` hard-wraps to the box width — nvim
cannot draw virt_text on the wrapped segments of a buffer line, so a line longer than
the box would escape its right border.

## Approach

- Chrome is extmarks only (`sign_text`, `virt_text`, `virt_lines`, `line_hl_group`);
  box characters never enter the buffer text, so yank/copy stays clean.
- `STYLES` in `pi.render` holds one glyph set + palette per role; `paint_row`
  takes a style, so a new role is one table entry.
- **Each box owns an extmark namespace** (`pi_box_<n>`) and is repainted by
  wiping that namespace. Range-scoped clears do not work here: `virt_lines` plus
  `nvim_buf_set_lines` on a boxed line shifts the stored row of that line's
  marks, so a cleared range misses them and marks accumulate per stream delta.
  For the same reason `jump_message` reads box starts from the Lua box records,
  not from extmark rows.
- Streaming boxes (thinking, tool batches) are opened on the first row, grown to
  the current last row, and closed by the next role transition. A tool block of
  argument lines is one box row range, and consecutive tool blocks join into one box.
- Text-level highlights live in their own `pi_role` namespace so box repaints never
  wipe the gray italic thinking text or the red error lines.
- `WinResized` / `VimResized` repaints every remembered box so borders track the
  chat window width.

## Out of scope

Bullet-list tool UI (`● path`), per-tool-kind colors, boxed assistant text,
tool *results* (only failures show their text), box characters written into the
yankable buffer.
