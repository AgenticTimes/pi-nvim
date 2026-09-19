local M = {}

function M.setup(opts)
  require("pi.config").setup(opts)
  local keys = require("pi.config").opts.keys
  if keys.toggle then
    vim.keymap.set("n", keys.toggle, function()
      require("pi").toggle()
    end, { desc = "pi: toggle UI" })
  end
end

function M.toggle()
  return require("pi.ui").toggle()
end

function M.stop()
  return require("pi.runtime").abort()
end

function M.accept()
  return require("pi.review").accept()
end

function M.reject()
  return require("pi.review").reject()
end

function M.diff_next()
  return require("pi.review").next(1)
end

function M.diff_prev()
  return require("pi.review").next(-1)
end

return M
