local M = {}

function M.setup(opts)
  require("pi.config").setup(opts)
  local keys = require("pi.config").opts.keys
  if keys.toggle then
    vim.keymap.set({ "n", "x" }, keys.toggle, function()
      local mode = vim.fn.mode()
      if mode == "v" or mode == "V" or mode == "\22" then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
      end
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

function M.cycle_model()
  return require("pi.runtime").cycle_model()
end

function M.pick_model()
  return require("pi.runtime").pick_model()
end

function M.cycle_thinking()
  return require("pi.runtime").cycle_thinking()
end

function M.pick_thinking()
  return require("pi.runtime").pick_thinking()
end

function M.toggle_fullscreen()
  return require("pi.ui").toggle_fullscreen()
end

function M.pick_session()
  return require("pi.sessions").pick()
end

function M.run(message, opts)
  return require("pi.runtime").run(message, opts)
end

function M.accept_all()
  return require("pi.review").accept_all()
end

function M.reject_all()
  return require("pi.review").reject_all()
end

function M.toggle_mode()
  return require("pi.runtime").toggle_mode()
end

function M.focus_toggle()
  return require("pi.ui").focus_toggle()
end

return M
