# Tool chrome label (summary on the top rule)

**Date:** 2026-10-03  
**Status:** approved

## Goal

Folded tool bubbles must answer “what happened?” from the **top rule alone**. Body args that only repeat that summary are noise (e.g. `⚙ subagent …` + `agent: worker`).

## Behavior

| Tool | Top-rule label | Body |
|------|----------------|------|
| `subagent` | `subagent · {agent}` (+ short task if room) | no `agent:` line; other args on expand |
| `bash` / `shell` | `$ {command}` truncated | no `$` dump when chrome has it |
| `read` / `grep` / path tools | basename / pattern | skip duplicated path/pattern |
| edit / write (existing) | path + `<C-r>` hint | mini-diff only |
| unknown | short tool name | full args (unchanged) |

Right-side hint stays `ftt to fold` / `ftt to expand` (edit keeps `<C-r> full diff`).

## Non-goals

- Multi-line labels
- Changing fold keys
