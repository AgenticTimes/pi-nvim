# Tool chrome label (summary on the top rule)

**Date:** 2026-10-03  
**Status:** approved (option 2: edit exception)

## Goal

Folded tool bubbles answer “what happened?” from the **top rule alone**. Never leave a bare `toolcall`. Only content-changing edit/write keep a body preview (mini-diff).

## Behavior

| Tool | Top-rule label | Body |
|------|----------------|------|
| `subagent` | `subagent · {agent}` (+ short task if room) | omit keys already on chrome |
| `bash` / `shell` | `$ {command}` truncated | omit one-line command |
| `read` / `grep` / path tools | basename / pattern | omit path/pattern |
| **any other non-edit tool** | `{short_name} · {best arg}` + mark | omit that arg when short |
| no useful args | `{short_name}` + mark | spacer |
| edit / write | path + `<C-r>` hint | **mini-diff preview only** |

### Generic arg pick order

`path` → `file` → `filename` → `command` → `pattern`/`regexp`/`query` → `agent` → `message`/`prompt`/`task`/`description`/`goal` → `url`/`uri` → `id`/`name`/`label` → first remaining short string (sorted keys).

Right-side hint stays `ftt to fold` / `ftt to expand` (edit keeps `<C-r> full diff`).

## Non-goals

- Multi-line labels
- Changing fold keys
- Replacing edit mini-diff with a plain chrome-only body
