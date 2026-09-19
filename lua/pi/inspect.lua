-- Inspect session: get_state / get_messages / get_entries → scratch JSON buffer
local M = {}

local buf ---@type integer|nil

local function ensure_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  buf = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, buf, "pi://inspect")
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "json"
  vim.bo[buf].modifiable = true
  return buf
end

local function show(lines, title)
  local b = ensure_buf()
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  -- open in split if not visible
  local shown
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == b then
      shown = w
      break
    end
  end
  if not shown then
    vim.cmd("botright 20split")
    shown = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(shown, b)
  else
    vim.api.nvim_set_current_win(shown)
  end
  pcall(vim.api.nvim_set_option_value, "winbar", " " .. (title or "pi inspect") .. " ", { win = shown })
  vim.bo[b].modifiable = false
end

local function pretty(obj)
  return vim.split(vim.inspect(obj, { indent = "  ", depth = 6 }), "\n", { plain = true })
end

function M.show_state()
  require("pi.runtime").ensure_started()
  local client = require("pi.client")
  local resp, err = client.request({ type = "get_state" }, require("pi.config").opts.rpc_timeout * 1000)
  if not resp then
    vim.notify("pi inspect state failed: " .. tostring(err), vim.log.levels.WARN)
    return
  end
  show(pretty(resp.data or resp), "pi state")
end

function M.show_messages()
  require("pi.runtime").ensure_started()
  local client = require("pi.client")
  local resp, err = client.request({ type = "get_messages" }, require("pi.config").opts.rpc_timeout * 1000)
  if not resp then
    vim.notify("pi inspect messages failed: " .. tostring(err), vim.log.levels.WARN)
    return
  end
  local data = resp.data or {}
  local messages = data.messages or data
  show(pretty(messages), "pi messages")
end

function M.show_entries()
  require("pi.runtime").ensure_started()
  local client = require("pi.client")
  local resp, err = client.request({ type = "get_entries" }, require("pi.config").opts.rpc_timeout * 1000)
  if not resp then
    vim.notify("pi inspect entries failed: " .. tostring(err), vim.log.levels.WARN)
    return
  end
  show(pretty(resp.data or resp), "pi entries")
end

function M.pick()
  vim.ui.select({
    { id = "state", label = "get_state" },
    { id = "messages", label = "get_messages" },
    { id = "entries", label = "get_entries" },
  }, {
    prompt = "pi inspect",
    format_item = function(it)
      return it.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    if choice.id == "state" then
      M.show_state()
    elseif choice.id == "messages" then
      M.show_messages()
    else
      M.show_entries()
    end
  end)
end

--- For tests: render object into lines without RPC
function M._format_for_test(obj)
  return pretty(obj)
end

return M
