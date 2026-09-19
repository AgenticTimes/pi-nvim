-- Skills picker (#) — skills come from get_commands with source "skill"
local slash = require("pi.slash")

local M = {}

function M.list()
  local cmds = slash.fetch()
  local skills = {}
  for _, c in ipairs(cmds) do
    if c.source == "skill" or (c.name and tostring(c.name):match("^skill:")) then
      table.insert(skills, c)
    end
  end
  return skills
end

function M.pick(on_select)
  local skills = M.list()
  if #skills == 0 then
    -- fallback: show all commands filtered by skill: prefix after refetch
    slash.invalidate()
    skills = M.list()
  end
  if #skills == 0 then
    vim.notify("pi: no skills from get_commands", vim.log.levels.INFO)
    return
  end
  vim.ui.select(skills, {
    prompt = "pi #skills",
    format_item = function(c)
      local name = tostring(c.name or ""):gsub("^skill:", "")
      local desc = c.description or ""
      if desc ~= "" then
        return string.format("#%s — %s", name, desc)
      end
      return "#" .. name
    end,
  }, function(choice)
    if choice and on_select then
      on_select(choice)
    end
  end)
end

function M.insert_into(buf)
  M.pick(function(choice)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local name = tostring(choice.name or "")
    if not name:match("^skill:") then
      name = "skill:" .. name
    end
    local text = "/" .. name .. " "
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
