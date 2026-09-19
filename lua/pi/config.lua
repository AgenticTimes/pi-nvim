local M = {}

M.opts = {
  executable = "pi",
  window = {
    width = 0.4,
    height = 0.9,
    border = "rounded",
    layout = "right",
  },
  keys = {
    toggle = "<leader>ai",
    submit = "<CR>",
    abort = "<C-c>",
    accept = "a",
    reject = "r",
    next_file = "]f",
    prev_file = "[f",
    mention = "@",
  },
  write_on_accept = true,
  rpc_timeout = 30,
}

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

function M.root()
  local src = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(src, ":p:h:h:h")
end

return M
