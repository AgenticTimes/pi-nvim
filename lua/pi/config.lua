local M = {}

M.opts = {
  executable = "pi",
  window = {
    width = 1.0,
    height = 1.0,
    border = "none",
    layout = "full",
    min_width = 56,
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
  },
  write_on_accept = true,
  rpc_timeout = 30,
  busy_submit = "steer", -- "steer" | "followUp" when agent is streaming
  --- stream thinking_delta into chat as ### thinking (before assistant text)
  show_thinking = true,
  --- "auto" = host tools enabled; "chat" = --no-tools (no tool calls)
  mode = "auto",
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
