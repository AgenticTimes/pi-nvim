# Review accept-all + return to chat

## Goal

1. Diff page has a clear **accept/reject all** key (not only `:PiAcceptAll`).
2. When the pending queue empties after Accept/Reject, return to the pi chat UI instead of leaving the user on a bare file buffer.

## Behavior

### Keys (review buffers only)

| Key | Action |
|-----|--------|
| `a` / `r` | Accept / reject current file (unchanged) |
| `A` / `R` | Accept / reject **all** pending files |
| `ah` / `rh` | Hunk accept / reject (unchanged) |

Hint virt_line + pending list help text mention `A`/`R`.

### After queue empties (`finish_empty`)

1. Tear down review chrome (existing `M.close`).
2. Ensure pi UI is open and **focus chat** (`ui.open` / `focus_chat`).
3. Notify briefly:
   - busy: `pi: no more diffs · waiting for agent…`
   - idle: `pi: review done`

### New diffs while busy

Unchanged: host tool edits already call `review.auto_show()` → reopen review when new pending arrives.

## Out of scope

- Changing `a`/`ah` timeout interaction
- Host `<leader>aA` wiring (optional follow-up in nvim config)
