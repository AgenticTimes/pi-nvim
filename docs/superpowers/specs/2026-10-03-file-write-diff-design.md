# File-write mini-diff (path-parse)

**Date:** 2026-10-03  
**Status:** approved (scope 2 / approach A)

## Goal

Any tool call that writes a file **and** whose path we can parse shows the same mini-diff chrome as host `replace_in_buffer` (path + `<C-r>` on the frame, +/- in the body).

## Coverage

| Source | Path from | Before snapshot |
|--------|-----------|-----------------|
| `replace*` / `write` / `edit` | `args.path` | `session.touched` if present, else disk at `tool_start` |
| `bash` | redirect / `tee` / `cat > path <<` | disk at `tool_start` |

## Bash parse (conservative)

- `>` / `>>` target
- `tee` / `tee -a` target
- `cat > path <<` / `cat <<… > path`

Skip `/dev/null`, fd redirects (`>&2`), variables (`$foo`).

## Behavior

- `tool_start`: snapshot lines per path (missing file → `{}`).
- `tool_end` success + content changed → mini-diff body + chrome; also `record_edit` so `<C-r>` works.
- Multiple files → first changed only.
- No parseable path / no change → keep normal tool block.

## Non-goals

- Dynamic paths inside scripts
- Full multi-file gallery in one bubble
