local M = {}

local function selection_text()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    -- try marks from last visual
    local s = vim.fn.getpos("'<")
    local e = vim.fn.getpos("'>")
    if s[2] == 0 or e[2] == 0 then
      return nil
    end
    local lines = vim.api.nvim_buf_get_lines(0, s[2] - 1, e[2], false)
    if #lines == 0 then
      return nil
    end
    return table.concat(lines, "\n")
  end
  return nil
end

function M.gather()
  local path = vim.api.nvim_buf_get_name(0)
  local diags = {}
  for _, d in ipairs(vim.diagnostic.get(0)) do
    table.insert(diags, string.format("L%d: %s", d.lnum + 1, d.message))
  end
  return {
    file = path ~= "" and path or nil,
    selection = selection_text(),
    diagnostics = diags,
  }
end

function M.expand(text)
  if type(text) ~= "string" then
    return text
  end
  local out = text
  if out:find("@this", 1, true) then
    local sel = selection_text()
    if not sel then
      local line = vim.api.nvim_get_current_line()
      sel = line
    end
    out = out:gsub("@this", sel or "")
  end
  if out:find("@buffer", 1, true) then
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    out = out:gsub("@buffer", table.concat(lines, "\n"))
  end
  if out:find("@diagnostics", 1, true) then
    local g = M.gather()
    local block = #g.diagnostics > 0 and table.concat(g.diagnostics, "\n") or "(no diagnostics)"
    out = out:gsub("@diagnostics", block)
  end
  return out
end

function M.preamble()
  local g = M.gather()
  local parts = {}
  if g.file then
    table.insert(parts, "Current file: " .. g.file)
  end
  if g.selection then
    table.insert(parts, "Selection:\n" .. g.selection)
  end
  if g.diagnostics and #g.diagnostics > 0 then
    table.insert(parts, "Diagnostics:\n" .. table.concat(g.diagnostics, "\n"))
  end
  return table.concat(parts, "\n\n")
end

function M.pick_file(cb)
  local root = vim.fn.getcwd()
  local files = {}
  if vim.fn.isdirectory(root .. "/.git") == 1 then
    files = vim.fn.systemlist({ "git", "-C", root, "ls-files" })
  else
    files = vim.fn.glob(root .. "/**/*", false, true)
  end
  vim.ui.select(files, { prompt = "pi @file" }, function(item)
    if item and cb then
      cb(item)
    end
  end)
end

return M
