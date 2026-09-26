# Chat markdown isolation

## Problem

Chat uses `filetype=markdown` plus Pi’s own extmark boxes. Host plugins like `render-markdown.nvim` also attach to `markdown` / `nofile`, adding conceal, heading/code overlays, and table virt lines that collide with box chrome (misaligned borders, double tables, flicker).

## Goal

Keep readable markdown syntax highlighting in chat without third-party markdown *renderers* attaching.

## Approach (chosen)

1. Chat buffer filetype → `pi-chat` (not `markdown`).
2. Register Treesitter: `vim.treesitter.language.register("markdown", "pi-chat")`.
3. **Explicitly** `vim.treesitter.start(buf, "markdown")` — nvim-treesitter only auto-starts on `FileType=markdown`, so register alone leaves chat unhighlighted.
4. Best-effort `pcall(require("render-markdown").buf_disable)` after setup (no hard dependency).
5. Ask input stays `markdown` (short editable draft; less box conflict).

## Out of scope

- Custom heading/code/fence chrome inside assistant boxes
- Changing host `render-markdown` global config (LSP hover `nofile` still ok)

## Success

- Chat `filetype` is `pi-chat`
- Suite green; box/table tests unchanged
- With `render-markdown` installed, chat does not get its overlays
