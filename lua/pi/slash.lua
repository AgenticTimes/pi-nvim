-- Slash command cache + picker (pi get_commands)
local M = {}

local cache = { cmds = {}, fetched_at = 0 }

function M.invalidate()
  cache.cmds = {}
  cache.fetched_at = 0
end

function M.fetch(force)
  if not force and #cache.cmds > 0 and (os.time() - cache.fetched_at) < 60 then
    return cache.cmds
  end
  require("pi.runtime").ensure_started()
  local client = require("pi.client")
  local resp, err = client.request({ type = "get_commands" }, require("pi.config").opts.rpc_timeout * 1000)
  if not resp or not resp.success then
    vim.notify("pi: get_commands failed: " .. tostring(err or (resp and resp.error)), vim.log.levels.WARN)
    return cache.cmds
  end
  local data = resp.data or {}
  cache.cmds = data.commands or data or {}
  cache.fetched_at = os.time()
  return cache.cmds
end

function M.pick(on_select)
  local cmds = M.fetch()
  if #cmds == 0 then
    vim.notify("pi: no slash commands", vim.log.levels.INFO)
    return
  end
  vim.ui.select(cmds, {
    prompt = "pi /commands",
    format_item = function(c)
      local name = c.name or "?"
      local desc = c.description or ""
      local src = c.source or ""
      if desc ~= "" then
        return string.format("/%s — %s [%s]", name, desc, src)
      end
      return "/" .. name
    end,
  }, function(choice)
    if choice and on_select then
      on_select(choice)
    end
  end)
end

---@param buf integer
function M.insert_into(buf)
  M.pick(function(choice)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local text = "/" .. (choice.name or "")
    if not text:match("%s$") then
      text = text .. " "
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cur = table.concat(lines, "\n")
    if cur:match("^%s*$") then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
    else
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(cur .. text, "\n", { plain = true }))
    end
    vim.cmd("startinsert!")
  end)
end

return M
