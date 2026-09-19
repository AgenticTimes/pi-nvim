local M = {}
local handlers = {}

function M.on(typ, cb)
  handlers[typ] = handlers[typ] or {}
  table.insert(handlers[typ], cb)
end

function M.fire(ev)
  vim.g.pi_event = ev
  pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "PiEvent", modeline = false })
  for _, cb in ipairs(handlers[ev.type] or {}) do
    pcall(cb, ev)
  end
  for _, cb in ipairs(handlers["*"] or {}) do
    pcall(cb, ev)
  end
end

return M
