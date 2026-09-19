local M = {}

local function extension_path()
  return require("pi.config").root() .. "/extensions/nvim_host_tools.ts"
end

local function on_event(ev)
  require("pi.session").on_event(ev)
  require("pi.events").fire(ev)
  pcall(function()
    require("pi.ui").on_event(ev)
  end)

  if ev.type == "extension_ui_request" then
    local resp = require("pi.host_tools").handle_ui_request(ev)
    if resp then
      require("pi.client").send(resp)
      require("pi.review").auto_show()
    end
  end
end

function M.ensure_started(opts)
  opts = opts or {}
  local client = require("pi.client")
  if client.is_running() then
    return
  end
  local config = require("pi.config")
  local exe = config.opts.executable or "pi"
  local ext = extension_path()
  local cmd = opts.cmd
    or {
      exe,
      "--mode",
      "rpc",
      "--no-extensions",
      "--no-builtin-tools",
      "-t",
      "nvim_replace_in_buffer,nvim_read_buffer",
      "-e",
      ext,
    }
  if opts.no_session then
    table.insert(cmd, 4, "--no-session")
  end
  client.start({
    cmd = cmd,
    cwd = opts.cwd or vim.fn.getcwd(),
    on_event = on_event,
  })
  client.set_on_event(on_event)
end

function M.prompt(message)
  M.ensure_started()
  require("pi.client").send({ type = "prompt", message = message })
end

function M.abort()
  local client = require("pi.client")
  if client.is_running() then
    client.send({ type = "abort" })
  end
end

function M.new_session()
  M.ensure_started()
  require("pi.client").send({ type = "new_session" })
  require("pi.session").reset()
end

function M.stop_job()
  require("pi.client").stop()
end

return M
