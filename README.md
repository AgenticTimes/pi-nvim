# pi.nvim

Neovim-native frontend for [pi](https://github.com/earendil-works/pi) coding agent.

**Wave 1:** chat/input UI · `pi --mode rpc` · host tools (`nvim_replace_in_buffer` / `nvim_read_buffer`) · multi-file review with **Accept / Reject**.

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

In review buffers: `a` accept (write + remove from list), `r` reject (restore), `]f`/`[f` next/prev file.

Default toggle: `<leader>ai`.

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
