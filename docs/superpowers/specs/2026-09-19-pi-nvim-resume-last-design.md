# Resume last session (same cwd)

## Behavior

- `,ai` / first `ensure_started`: if `resume_last` (default true) and cwd has sessions, `switch_session` to newest jsonl, then hydrate chat from `get_messages`.
- `,aI` / `:PiNewSession`: `no_resume`, start fresh, clear chat.
- `,as` / `:PiSessions`: pick → switch → hydrate (not just `· switched session`).
- Mode toggle restart: re-attach current `sessionFile` if known.

## Async hydrate (important)

`get_messages` must **not** use `client.request`/`vim.wait` inside the job `on_stdout` callback — that deadlocks the UI (`hydrate failed: timeout`). Flow:

1. `switch_session` success → `vim.schedule` → `hydrate_chat` sends `{ type=get_messages, id=hydrate-msgs }`
2. Response with that id → `vim.schedule` → `render.hydrate`

## Scope

- Reuse `~/.pi/agent/sessions/--cwd--/*.jsonl` — no extra pointer file.
- Hydrate shows user/assistant text; collapse toolCalls; skip toolResult bodies.

## Config

```lua
resume_last = true
```
