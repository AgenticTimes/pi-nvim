# pi.nvim

Neovim-native frontend for [pi](https://github.com/earendil-works/pi) coding agent.

**Wave 1:** chat/input UI · `pi --mode rpc` · host tools (`nvim_replace_in_buffer` / `nvim_read_buffer`) · multi-file review with **Accept / Reject**.

**Wave 2:** busy steer/follow-up · history · model/thinking · fullscreen · session picker · slash `/` · Tab · `]]`/`[[` · Accept/Reject all · `:PiRun` · `nvim_open`/`nvim_goto`.

**Wave 3:** approve modes (`ask`/`smart`/`auto`/`deny` + Always) · `#` skills · hunk `ah`/`rh`/`]h`/`[h` · `:PiExportHtml` · `:PiInspect` · `@visible` · chat/auto · focus · session name · **resume last session** (same cwd).

## Requirements

- Neovim ≥ 0.10
- `pi` ≥ 0.84 on `PATH`

## Install (lazy.nvim)

```lua
{
  dir = "~/source/pi.nvim", -- or git url when published
  lazy = false,
  config = function()
    require("pi").setup({
      keys = { toggle = "<leader>ai" },
      write_on_accept = true,
    })
  end,
}
```

## Usage

| Command | Action |
|---------|--------|
| `:Pi` | Toggle chat UI |
| `:PiStop` | Abort agent |
| `:PiNewSession` | New session |
| `:PiDiff` | Open review |
| `:PiAccept` / `:PiReject` | Accept / reject current pending file |
| `:PiCycleModel` | Cycle model |
| `:PiCycleThinking` | Cycle thinking level |
| `:PiFullscreen` | Toggle fullscreen chat |
| `:PiSessions` | Pick session for cwd (also hydrates chat) |
| `:PiRun {msg}` | Open UI + prompt |
| `:PiAcceptAll` / `:PiRejectAll` | Accept / reject all pending |
| `:PiSlash` | Pick slash command |

On first open (`,ai`), if `resume_last = true` (default), switches to the newest session for the current cwd and fills the chat from history. `,aI` / `:PiNewSession` always starts fresh.

In review buffers: `a` accept, `r` reject, `]f`/`[f` next/prev.

In chat: `<CR>` open ask popup · `]]`/`[[` next/prev message · `q` close · `<Tab>` toggle ask.

In ask popup: `<CR>` newline · `<C-CR>` / `<D-CR>` submit · normal-mode `<CR>` submit · `<Esc>` close popup · `<C-c>` abort · `<Up>`/`<Down>` history · empty `/` slash · `@` mention · empty `#` skills.

Suggested keys: `<leader>ai` toggle (auto-resume) · `<leader>aI` new session · `<leader>as` sessions · `<leader>av` inspect · `<leader>ap` approve mode · `<leader>ah` export HTML · `<leader>ae` focus · `<leader>ac` chat/auto · `<leader>an` name · `<leader>am`/`at` model/thinking · `<leader>aF` fullscreen · `<leader>aA`/`aR` accept/reject all.

Placeholders in prompts: `@this` `@buffer` `@visible` `@diagnostics` · empty `/` slash · empty `#` skills.

## Tests

```bash
cd ~/source/pi.nvim && nvim -u NONE -l tests/run.lua
```

## Spike demos (still available)

```bash
nvim demo/sample.lua -c "luafile scripts/demo_toolcall_ui.lua"
cd ~/source/pi.nvim && nvim -c "luafile scripts/demo_multifile_ui.lua"
```

## Spec / plan

- `docs/superpowers/specs/2026-09-19-pi-nvim-goose-parity-design.md`
- `docs/superpowers/plans/2026-09-19-pi-nvim-wave1.md`
