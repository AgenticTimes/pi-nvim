-- Quiet notifications that won't trip cmdheight=0 hit-enter prompts.
local M = {}

---@param msg string
---@param level integer|nil
function M.soft_notify(msg, level)
  msg = tostring(msg or ""):gsub("[\r\n\t]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
  if msg == "" then
    return
  end
  msg = msg:sub(1, 160)
  level = level or vim.log.levels.INFO

  -- Dedicated UIs that don't use the cmdline.
  if package.loaded["notify"] then
    pcall(vim.notify, msg, level, { title = "pi", render = "minimal" })
    return
  end
  if pcall(require, "noice") then
    pcall(vim.notify, msg, level, { title = "pi" })
    return
  end

  -- cmdheight=0: any cmdline message → "Press ENTER to continue". Stay silent.
  if (tonumber(vim.o.cmdheight) or 0) == 0 then
    return
  end
  pcall(vim.notify, msg, level)
end

return M
