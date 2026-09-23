# Busy statusline (Working spinner)

## Goal

After the user submits a prompt, show that pi is still working even when the ask
popup is closed and focus is back in the editor. Prefer Neovim statusline over
chat-bottom chrome.

## Why not chat-bottom / ask-footer

- Ask popup closes on submit → a line painted on the input float disappears.
- Chat-bottom footer is easy to miss once the user leaves the chat window.
- Statusline (`globalstatus`) stays visible across floats and editor focus.

## Approach

### Signal

Reuse existing busy state in `pi.session`:

- `agent_start` / `isStreaming == true` → busy
- `agent_end` / `isStreaming == false` / abort → idle

Do not invent a second busy flag.

### Module: `lua/pi/statusline.lua`

- `start()` on busy: record `vim.uv.hrtime()`, start a uv timer (~100ms).
- Each tick: advance braille frame (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`), call `refresh()`.
- `stop()` on idle: stop timer, clear text, refresh once.
- `text()` / `lualine()`: idle → `""`; busy → `⠋ Working · Ns` (elapsed seconds).
- Highlight: soft warning / muted (e.g. `WarningMsg` or a `PiBusy` hl), not mode-colored.

`refresh()`: `pcall(require("lualine").refresh, { place = { "statusline" } })` when
lualine is loaded; otherwise no-op (component still works if wired later).

### Wire into host config

In `~/.config/nvim/lua/plugins/statusline.lua`, prepend to `lualine_x`:

```lua
{
  function()
    return require("pi.statusline").lualine()
  end,
  cond = function()
    return require("pi.statusline").lualine() ~= ""
  end,
},
```

pi.nvim itself does not patch the user's lualine setup automatically.

### Event hooks

- `pi.session.on_event` / `apply_state`: when status flips to streaming →
  `require("pi.statusline").start()`; to idle → `stop()`.
- `pi.runtime.abort`: ensure `stop()`.

## Out of scope

- Chat transcript `Working…` line / extmark.
- Traveling line under the ask popup.
- Auto-detecting and mutating arbitrary statusline plugins beyond documenting
  the lualine component.
- Showing tool name / model in the busy string (elapsed only for v1).

## Acceptance

1. Submit a prompt → statusline shows a spinning `Working · Ns` within ~100ms.
2. Switch focus to a normal buffer → spinner still visible (`globalstatus`).
3. Agent finishes or abort → spinner gone on the next refresh.
4. Idle → `lualine()` returns `""` (no empty separators left behind when
   `cond` is used).
