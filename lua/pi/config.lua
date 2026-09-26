local M = {}

M.opts = {
  executable = "pi",
  window = {
    width = 1.0,
    height = 1.0,
    border = "rounded",
    --- "full" = edge-to-edge opaque; "float" = inset translucent overlay
    layout = "float",
    min_width = 56,
    --- 0–100; only applied when layout is "float". 0 = opaque (hides
    --- file explorer / buffers behind the agent UI).
    winblend = 0,
  },
  keys = {
    toggle = "<leader>ai",
    submit = "<CR>", -- Enter submits (n + i); terminals rarely send distinct C-CR / S-CR
    newline = "<C-j>", -- Ctrl+J inserts newline (portable); S-CR also when terminal supports it
    abort = "<C-c>",
    accept = "a",
    reject = "r",
    next_file = "]f",
    prev_file = "[f",
    mention = "@",
    history_prev = "<Up>",
    history_next = "<Down>",
    steer = "<C-s>",
    slash = "/",
    skill = "#",
    focus_cycle = "<Tab>",
    next_message = "]]",
    prev_message = "[[",
    --- M2 multi-slot
    slot_new = "<leader>a+",
    slot_close = "<leader>a_",
    slot_cycle = "<leader>a>",
    slot_idle = "<leader>a.",
    --- Promote slot to master: `12<leader>w` or `<leader>w` then digits.
    slot_focus = "<leader>w",
  },
  --- Global summon/hide (M1 primary float). Independent of keys.toggle.
  summon_key = "<C-Space>",
  --- On VimEnter: start RPC in background (no UI); notify when ready.
  bootstrap = true,
  --- Safety ceiling only; real limit is geometry with master shrunk to
  --- slot_min_width and satellites packed in the rest (see slots.capacity).
  max_slots = 64,
  --- Minimum float cell size; vertical fill first, then horizontal splits.
  slot_min_width = 24,
  slot_min_height = 6,
  write_on_accept = true,
  rpc_timeout = 30,
  busy_submit = "steer", -- "steer" | "followUp" when agent is streaming
  --- stream thinking as gray text (no role labels; OpenCode-style)
  show_thinking = true,
  --- "auto" = builtins + nvim host tools; "chat" = --no-tools
  mode = "auto",
  --- Soft tool preference (pi has no priority API). Default drops disk
  --- edit/write so nvim_replace_in_buffer owns buffer mutations. Set to ""
  --- or {} for a full builtin set including edit/write. bash/read/grep stay on.
  tools_exclude = { "edit", "write" },
  --- confirm dialogs: ask | smart | auto | deny
  approve = "ask",
  --- after export_html, open the file (edit / system open)
  export_open = true,
  --- on first RPC start, switch to newest session for cwd and hydrate chat
  resume_last = true,
}

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

function M.root()
  local src = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(src, ":p:h:h:h")
end

return M
