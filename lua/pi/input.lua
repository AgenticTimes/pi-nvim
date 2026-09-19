local config = require("pi.config")
local context = require("pi.context")

local M = {}
local buf ---@type integer|nil
local history = {}

function M.set_buffer(b)
  buf = b
end

function M.buffer()
  return buf
end

function M.setup(b, on_close)
  buf = b
  vim.bo[b].buftype = "nofile"
  vim.bo[b].bufhidden = "hide"
  vim.bo[b].filetype = "markdown"
  local k = config.opts.keys
  local opts = { buffer = b, nowait = true, silent = true }
  vim.keymap.set({ "n", "i" }, k.submit, function()
    M.submit()
  end, opts)
  vim.keymap.set({ "n", "i" }, k.abort, function()
    M.abort()
  end, opts)
  if k.mention then
    vim.keymap.set("i", k.mention, function()
      context.pick_file(function(path)
        local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
        local cur = table.concat(lines, "\n")
        vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.split(cur .. " @" .. path .. " ", "\n", { plain = true }))
        vim.cmd("startinsert!")
      end)
    end, opts)
  end
  if on_close then
    vim.keymap.set("n", "q", on_close, opts)
  end
end

function M.submit()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then
    return
  end
  table.insert(history, text)
  local expanded = context.expand(text)
  local pre = context.preamble()
  local message = pre ~= "" and (pre .. "\n\n" .. expanded) or expanded
  local ui = require("pi.ui")
  local chat = ui.chat_buf()
  if chat then
    local render = require("pi.render")
    render.append(chat, "")
    render.append(chat, "### you")
    render.append(chat, text)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  require("pi.runtime").prompt(message)
end

function M.abort()
  require("pi.runtime").abort()
end

return M
