# pi.nvim Wave 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a usable Neovim-native pi coding-agent UI: RPC client, host file tools (buffer API), chat+input, context/@, and multi-file review with Accept/Reject.

**Architecture:** Neovim hosts `pi --mode rpc` over JSONL. A pi extension registers `nvim_*` tools and disables builtin `edit`/`write`/`read`. Tools round-trip via `extension_ui_request`/`response`. Edits apply to buffers first; `review` tracks pending files with BEFORE snapshots for Accept (keep + write + drop) / Reject (restore + drop).

**Tech Stack:** Neovim ≥ 0.10 Lua, `pi` CLI ≥ 0.84 (`@earendil-works/pi-coding-agent`), TypeScript pi extension, headless `nvim -l` tests (no plenary required for MVP).

**Spec:** `docs/superpowers/specs/2026-09-19-pi-nvim-goose-parity-design.md` (Wave 1 only).

## Global Constraints

- No embedded pi TUI as default UI.
- Do not reimplement the LLM agent loop; use `pi --mode rpc`.
- File mutations for agent edits go through Neovim APIs (host tools), not pi builtin disk `edit`/`write`.
- Review policy: apply-then-review; Accept removes from pending list; Reject restores BEFORE.
- Zero third-party Neovim runtime deps for MVP (optional picker later via `vim.ui.select` fallback).
- Keep spike demos under `scripts/` working until product `:Pi` replaces them.
- Repo root: `/Users/meetai/source/pi.nvim` (init git on first commit if missing).

## File Structure (create)

```
pi.nvim/
├── extensions/nvim_host_tools.ts
├── lua/pi/
│   ├── init.lua          -- setup, public API
│   ├── config.lua
│   ├── client.lua        -- job + JSONL framing
│   ├── session.lua       -- state machine + messages + touched
│   ├── host_tools.lua    -- handle extension_ui_request ops
│   ├── review.lua        -- diff UI, accept/reject, ]f/[f
│   ├── context.lua       -- expand placeholders / gather
│   ├── ui.lua            -- float/split chat+input layout
│   ├── input.lua         -- send/abort/history keys
│   ├── render.lua        -- append messages to chat buf
│   └── events.lua        -- User PiEvent
├── plugin/pi.lua         -- commands
├── tests/
│   ├── run.lua
│   ├── helpers.lua
│   ├── fake_pi.mjs       -- RPC double for unit tests
│   ├── client_test.lua
│   ├── host_tools_test.lua
│   ├── review_test.lua
│   └── context_test.lua
└── README.md             -- update install + Wave 1 usage
```

---

### Task 1: Repo bootstrap + test harness

**Files:**
- Create: `tests/helpers.lua`, `tests/run.lua`, `tests/fake_pi.mjs`
- Create: `plugin/pi.lua` (stub commands)
- Create: `lua/pi/init.lua`, `lua/pi/config.lua` (stubs)
- Modify: `README.md` (point to product path)
- Test: `tests/run.lua`

**Interfaces:**
- Produces: `require("pi").setup(opts)` merges into `require("pi.config").opts`
- Produces: `tests/helpers.lua` → `with_nvim(fn)`, `assert_eq(a,b,msg)`

- [ ] **Step 1: Init git (if needed) and create stub modules**

```bash
cd /Users/meetai/source/pi.nvim
git init
```

`lua/pi/config.lua`:
```lua
local M = {}
M.opts = {
  executable = "pi",
  window = { width = 0.4, height = 0.9, border = "rounded", layout = "right" },
  keys = {
    toggle = "<leader>ai",
    submit = "<CR>",
    abort = "<C-c>",
    accept = "a",
    reject = "r",
    next_file = "]f",
    prev_file = "[f",
  },
  write_on_accept = true,
}
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end
return M
```

`lua/pi/init.lua`:
```lua
local M = {}
function M.setup(opts)
  require("pi.config").setup(opts)
end
return M
```

`plugin/pi.lua`:
```lua
vim.api.nvim_create_user_command("Pi", function()
  vim.notify("pi.nvim: not wired yet", vim.log.levels.WARN)
end, {})
```

- [ ] **Step 2: Write test harness + one smoke test file**

`tests/helpers.lua` — assert helpers and path to root.

`tests/run.lua` — load all `*_test.lua` under tests/, exit 1 on failure.

`tests/fake_pi.mjs` — stdin JSONL; on `prompt` emit `agent_start`, optional scripted `extension_ui_request` if message contains `FORCE_HOST_EDIT`, then `agent_end`. Keep minimal (expand in Task 2–3).

- [ ] **Step 3: Run harness (expect pass with empty/smoke)**

```bash
cd /Users/meetai/source/pi.nvim && nvim -u NONE -l tests/run.lua
```
Expected: exit 0 (or “0 tests” then add `tests/smoke_test.lua` asserting `require("pi.config").opts.keys.accept == "a"`).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: bootstrap pi.nvim Wave 1 stubs and test harness"
```

---

### Task 2: RPC client (JSONL framing + request/response)

**Files:**
- Create: `lua/pi/client.lua`
- Create: `tests/client_test.lua`
- Modify: `tests/fake_pi.mjs` (respond to `prompt` / `abort` / `get_state`)

**Interfaces:**
- Produces:
  - `client.start({ cmd, args, cwd, on_event, on_exit }) -> job_id`
  - `client.send(obj)`
  - `client.request(obj, timeout_ms) -> response|nil, err`
  - `client.stop()`
- Consumes: `config.opts.executable`

- [ ] **Step 1: Failing test — framing accumulates partial chunks**

```lua
-- tests/client_test.lua
local client = require("pi.client")
-- feed two chunks of one JSON line; expect one on_event
```

- [ ] **Step 2: Implement `client.lua` with line buffer, `chansend`, pending id map**

Match spike semantics from `scripts/demo_toolcall_ui.lua` stdout loop. Only split on `\n`.

- [ ] **Step 3: Integration with `fake_pi.mjs`**

Start node fake as job; `request({type="prompt",id="1",message="hi"})` gets `{type="response",success=true}`.

- [ ] **Step 4: Run tests**

```bash
nvim -u NONE -l tests/run.lua
```
Expected: client tests PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(client): JSONL RPC client for pi --mode rpc"
```

---

### Task 3: Host tools bridge + pi extension

**Files:**
- Create: `extensions/nvim_host_tools.ts`
- Create: `lua/pi/host_tools.lua`
- Create: `tests/host_tools_test.lua`
- Modify: `tests/fake_pi.mjs` (emit `extension_ui_request` for host ops)

**Interfaces:**
- Extension tools: `nvim_replace_in_buffer`, `nvim_read_buffer`
- Extension startup: exclude/override builtins via documenting CLI flags `--no-builtin-tools -t nvim_replace_in_buffer,nvim_read_buffer` (and register both in extension)
- Produces: `host_tools.handle_ui_request(req) -> response_payload`
  - ops: `replace_in_buffer {path,old_text,new_text}`, `read_buffer {path}`
- HOST_TITLE constant `"__nvim_host__"` (same as spike)

- [ ] **Step 1: Failing test — replace_in_buffer changes buffer and returns ok**

Open temp file buffer; call `host_tools.apply({op="replace_in_buffer",...})`; assert lines + BEFORE snapshot returned for session.

- [ ] **Step 2: Implement `host_tools.lua`**

Port logic from `scripts/demo_multifile_ui.lua` / `demo_toolcall_ui.lua` (loose indent match).

- [ ] **Step 3: Implement `extensions/nvim_host_tools.ts`**

`registerTool` for replace + read; `ctx.ui.input(HOST_TITLE, JSON.stringify(op))`.

- [ ] **Step 4: Wire client `on_event` for `extension_ui_request` → `host_tools` → `extension_ui_response`**

In a small `runtime.lua` or inside `session` start path (prefer `lua/pi/runtime.lua` create now if cleaner):

- Create: `lua/pi/runtime.lua` with `runtime.ensure_started()` spawning:
  `pi --mode rpc --no-session --no-extensions --no-builtin-tools -t nvim_replace_in_buffer,nvim_read_buffer -e <root>/extensions/nvim_host_tools.ts`

- [ ] **Step 5: Optional live test (needs real `pi` + model) — document in README**

```bash
nvim demo/sample.lua -c "luafile scripts/demo_toolcall_ui.lua"
```
Keep spike as regression until Task 6.

- [ ] **Step 6: Commit**

```bash
git commit -am "feat(host): nvim_* tools via extension_ui bridge"
```

---

### Task 4: Session state + review (pending list, diff, accept/reject)

**Files:**
- Create: `lua/pi/session.lua`, `lua/pi/review.lua`
- Create: `tests/review_test.lua`
- Modify: `lua/pi/host_tools.lua` to call `session.record_edit(...)`

**Interfaces:**
- `session.touched` list: `{ path, rel, before, buf, changed_row }`
- `session.record_edit(entry)`
- `review.open(idx)`, `review.next(delta)`, `review.accept()`, `review.reject()`, `review.close()`
- Accept: optional `write_on_accept`; remove from `touched`; show next or empty
- Reject: restore `before`; remove from list

- [ ] **Step 1: Failing tests**

1. After two `record_edit`, `#session.touched()==2`
2. `accept()` shrinks to 1 and keeps AFTER lines
3. `reject()` restores BEFORE lines

- [ ] **Step 2: Implement session + review**

Port multifile UI pieces into `review.lua` (list buf `pi://touched`, before `pi://before/<rel>`, diffthis). Buffer-local keys from `config.opts.keys`.

- [ ] **Step 3: Run tests**

```bash
nvim -u NONE -l tests/run.lua
```
Expected: review tests PASS.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(review): multi-file diff pending list with accept/reject"
```

---

### Task 5: Context gathering

**Files:**
- Create: `lua/pi/context.lua`
- Create: `tests/context_test.lua`

**Interfaces:**
- `context.expand(text) -> string` placeholders: `@this`, `@buffer`, `@diagnostics`
- `context.gather() -> { file, selection, diagnostics }` for prompt preamble
- `context.pick_file(cb)` using `vim.ui.select` over `git ls-files` or `vim.fn.globpath`

- [ ] **Step 1: Failing tests for `@this` / `@diagnostics` expansion**

- [ ] **Step 2: Implement `context.lua`**

- [ ] **Step 3: Run tests + commit**

```bash
git commit -am "feat(context): editor context placeholders and gather"
```

---

### Task 6: UI (chat + input) + render + input keys

**Files:**
- Create: `lua/pi/ui.lua`, `lua/pi/render.lua`, `lua/pi/input.lua`, `lua/pi/events.lua`
- Modify: `lua/pi/init.lua`, `plugin/pi.lua`
- Create: `tests/ui_test.lua` (open/close buffers exist)

**Interfaces:**
- `ui.toggle()`, `ui.open()`, `ui.close()`, `ui.is_open()`
- Chat buf `pi://chat`, input buf `pi://input`
- `input.submit()` → `context.expand` → `client.send{type="prompt",...}`
- `input.abort()` → `{type="abort"}`
- `render` handles `message_update` / `tool_execution_*` lines in chat
- `events.fire(ev)` → `User PiEvent` + `vim.g.pi_event`

- [ ] **Step 1: Failing test — after `ui.open()`, chat and input bufs exist**

- [ ] **Step 2: Implement layout (right float default from config)**

- [ ] **Step 3: Wire runtime start on first open; subscribe client events → render + host_tools + review.auto_show on edit**

- [ ] **Step 4: Commands**

```lua
:Pi          -> ui.toggle
:PiStop      -> abort
:PiNewSession -> new_session RPC
:PiDiff      -> review.open(1) or current
:PiAccept    -> review.accept
:PiReject    -> review.reject
```

- [ ] **Step 5: Manual checklist (document in README)**

1. `:Pi` opens UI  
2. Send prompt that forces tool (or use spike script)  
3. Pending list + diff appear  
4. `a` removes file from list  

- [ ] **Step 6: Commit**

```bash
git commit -am "feat(ui): goose-style chat/input wired to pi RPC"
```

---

### Task 7: Public API keymap setup + README polish

**Files:**
- Modify: `lua/pi/init.lua` (register global keymaps from config)
- Modify: `README.md`
- Modify: keep `scripts/demo_*.lua` as “legacy spike” section

**Interfaces:**
- `require("pi").setup({ keys = {...}, write_on_accept = true })`
- Exports: `toggle`, `stop`, `accept`, `reject`, `diff_next`, `diff_prev`

- [ ] **Step 1: Wire setup keymaps (default `<leader>ai` toggle)**

- [ ] **Step 2: Update README install (lazy.nvim), Wave 1 feature list, test commands**

```bash
nvim -u NONE -l tests/run.lua
cd ~/source/pi.nvim && nvim -c "luafile scripts/demo_multifile_ui.lua"  # spike still OK
```

- [ ] **Step 3: Commit**

```bash
git commit -am "docs: Wave 1 usage and keymap setup"
```

---

### Task 8: Wave 1 acceptance gate

**Files:** none (verification only)

- [ ] **Step 1: Run unit suite**

```bash
cd /Users/meetai/source/pi.nvim && nvim -u NONE -l tests/run.lua
```
Expected: all PASS.

- [ ] **Step 2: Live multifile + accept (real pi)**

```bash
cd /Users/meetai/source/pi.nvim && nvim -c "lua require('pi').setup({}); vim.cmd('Pi')"
```
Or spike: `nvim -c "luafile scripts/demo_multifile_ui.lua"` then press `a` thrice until list empty.

Expected: 3 TOOLCALLs; Accept clears pending.

- [ ] **Step 3: Confirm builtins do not write disk without host**

Inspect spawn args include `--no-builtin-tools` and only `nvim_*` tools.

- [ ] **Step 4: Tag / note Wave 1 done in README changelog section**

---

## Spec coverage (self-check)

| Spec Wave 1 item | Task |
|------------------|------|
| client + extension host tools | 2–3 |
| ui input+output | 6 |
| context file/selection/diagnostics/@ | 5 |
| session + review accept/reject |]f| | 4 |
| api toggle/stop/new_session/run | 6–7 |
| success criteria 1–4 | 8 |
| Spike mapping preserved | 3, 7 |

## Out of plan (Wave 2+)

steer/follow-up UX polish, fullscreen, session picker, model/thinking cycle, slash completion, approve modes, skills `#`.

---

Plan complete and saved to `docs/superpowers/plans/2026-09-19-pi-nvim-wave1.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — implement tasks in this session with checkpoints  

Which approach?
