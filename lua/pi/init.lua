local M = {}

function M.setup(opts)
  require("pi.config").setup(opts)
  local cfg = require("pi.config").opts
  local keys = cfg.keys
  if keys.toggle then
    vim.keymap.set({ "n", "x" }, keys.toggle, function()
      local mode = vim.fn.mode()
      if mode == "v" or mode == "V" or mode == "\22" then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
      end
      require("pi").toggle()
    end, { desc = "pi: toggle UI" })
  end
  local summon = cfg.summon_key
  if summon and summon ~= "" then
    -- normal/visual only: insert <C-Space> is commonly nvim-cmp complete
    vim.keymap.set({ "n", "x" }, summon, function()
      require("pi").toggle()
    end, { desc = "pi: summon / hide" })
  end
  if keys.slot_new then
    vim.keymap.set("n", keys.slot_new, function()
      local s, err = require("pi.slots").create()
      if not s then
        vim.notify("pi: " .. tostring(err), vim.log.levels.WARN)
      end
    end, { desc = "pi: new slot" })
  end
  if keys.slot_close then
    vim.keymap.set("n", keys.slot_close, function()
      require("pi.slots").close()
    end, { desc = "pi: close slot" })
  end
  if keys.slot_cycle then
    vim.keymap.set("n", keys.slot_cycle, function()
      require("pi.slots").cycle_primary(1)
    end, { desc = "pi: cycle primary slot" })
  end
  if keys.slot_idle then
    vim.keymap.set("n", keys.slot_idle, function()
      require("pi.slots").toggle_idle()
    end, { desc = "pi: hide/show idle slots" })
  end
  if keys.slot_focus and keys.slot_focus ~= "" then
    local prefix = keys.slot_focus
    for i = 1, 9 do
      vim.keymap.set("n", prefix .. tostring(i), function()
        require("pi.slots").focus_by_id(i)
      end, { desc = string.format("pi: focus slot #%d as master", i) })
    end
    vim.keymap.set("n", prefix .. "0", function()
      require("pi.slots").focus_by_id(10)
    end, { desc = "pi: focus slot #10 as master" })
  end
  if cfg.bootstrap then
    vim.api.nvim_create_autocmd("VimEnter", {
      once = true,
      callback = function()
        vim.schedule(function()
          pcall(function()
            require("pi.runtime").bootstrap()
          end)
        end)
      end,
    })
  end
end

function M.toggle()
  return require("pi.slots").toggle_visible()
end

function M.stop()
  return require("pi.runtime").abort()
end

--- Abort the in-flight LLM turn (RPC `abort`). Alias of `stop`.
function M.interrupt()
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

function M.compact(opts)
  return require("pi.runtime").compact(opts)
end

function M.set_auto_compaction(enabled)
  return require("pi.runtime").set_auto_compaction(enabled)
end

function M.toggle_auto_compaction()
  return require("pi.runtime").toggle_auto_compaction()
end

function M.focus_slot(n)
  return require("pi.slots").focus_by_id(n)
end

function M.toggle_idle()
  return require("pi.slots").toggle_idle()
end

return M
