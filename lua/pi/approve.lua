-- Handle non-host extension_ui_request: confirm / select / input dialogs
-- Modes: ask (default) | auto (always yes) | deny (always no) | smart (auto-yes for known-safe titles)
local config = require("pi.config")

local M = {}

local sticky_allow = false -- session-scoped "always allow" after user picks Always

local SAFE_TITLE_PATTERNS = {
  "^Allow read",
  "^Read ",
  "nvim_read",
  "^Confirm$",
}

function M.reset_sticky()
  sticky_allow = false
end

function M.set_mode(mode)
  if not vim.tbl_contains({ "ask", "auto", "deny", "smart" }, mode) then
    error("approve mode must be ask|auto|deny|smart")
  end
  config.opts.approve = mode
  vim.notify("pi: approve → " .. mode, vim.log.levels.INFO)
end

function M.cycle_mode()
  local order = { "ask", "smart", "auto", "deny" }
  local cur = config.opts.approve or "ask"
  local idx = 1
  for i, m in ipairs(order) do
    if m == cur then
      idx = i
      break
    end
  end
  M.set_mode(order[(idx % #order) + 1])
end

function M.mode()
  return config.opts.approve or "ask"
end

local function respond(id, fields)
  local msg = vim.tbl_extend("force", { type = "extension_ui_response", id = id }, fields)
  require("pi.client").send(msg)
end

local function is_safe_title(title)
  title = title or ""
  for _, pat in ipairs(SAFE_TITLE_PATTERNS) do
    if title:match(pat) then
      return true
    end
  end
  return false
end

local function decide_confirm(title)
  local mode = M.mode()
  if sticky_allow then
    return true
  end
  if mode == "auto" then
    return true
  end
  if mode == "deny" then
    return false
  end
  if mode == "smart" and is_safe_title(title) then
    return true
  end
  return nil -- need UI
end

local function confirm_ui(req)
  local title = req.title or "pi confirm"
  local message = req.message or ""
  local choice = vim.fn.confirm(
    title .. "\n" .. message,
    "&Yes\n&No\n&Always (this session)",
    1
  )
  if choice == 3 then
    sticky_allow = true
    return true
  end
  return choice == 1
end

function M.handle(req)
  if not req or req.type ~= "extension_ui_request" then
    return false
  end
  if req.title == require("pi.host_tools").HOST_TITLE then
    return false
  end

  local method = req.method or "input"
  if method == "confirm" then
    local decided = decide_confirm(req.title)
    if decided ~= nil then
      respond(req.id, { confirmed = decided })
      return true
    end
    vim.schedule(function()
      local ok = confirm_ui(req)
      respond(req.id, { confirmed = ok })
      pcall(function()
        local render = require("pi.render")
        local chat = require("pi.ui").chat_buf()
        render.append(chat, string.format("· approve %s → %s", req.title or "?", ok and "yes" or "no"))
      end)
    end)
    return true
  end

  if method == "select" then
    local options = req.options or req.choices or {}
    local labels = {}
    for i, opt in ipairs(options) do
      if type(opt) == "table" then
        labels[i] = opt.label or opt.value or vim.inspect(opt)
      else
        labels[i] = tostring(opt)
      end
    end
    if M.mode() == "auto" and #options > 0 then
      local value = options[1]
      if type(value) == "table" and value.value ~= nil then
        value = value.value
      end
      respond(req.id, { value = value })
      return true
    end
    if M.mode() == "deny" then
      respond(req.id, { cancelled = true })
      return true
    end
    vim.schedule(function()
      vim.ui.select(labels, { prompt = req.title or "pi select" }, function(item, idx)
        if not item then
          respond(req.id, { cancelled = true })
          return
        end
        local value = options[idx]
        if type(value) == "table" and value.value ~= nil then
          value = value.value
        end
        respond(req.id, { value = value })
      end)
    end)
    return true
  end

  if method == "input" then
    if M.mode() == "deny" then
      respond(req.id, { cancelled = true })
      return true
    end
    vim.schedule(function()
      vim.ui.input({
        prompt = (req.title or "pi") .. ": ",
        default = req.defaultValue or req.placeholder or "",
      }, function(text)
        if text == nil then
          respond(req.id, { cancelled = true })
        else
          respond(req.id, { value = text })
        end
      end)
    end)
    return true
  end

  if method == "notify" then
    vim.notify(tostring(req.message or req.title or "pi notify"), vim.log.levels.INFO)
    respond(req.id, { ok = true })
    return true
  end

  return false
end

return M
