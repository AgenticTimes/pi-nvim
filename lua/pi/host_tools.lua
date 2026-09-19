-- Execute host ops from extension_ui_request payloads
local session = require("pi.session")

local M = {}
M.HOST_TITLE = "__nvim_host__"

local function norm(p)
  return vim.fn.fnamemodify(p, ":p")
end

function M.buffer_for(path)
  local abs = norm(path)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= "" and norm(name) == abs then
        return b
      end
    end
  end
  return nil
end

function M.ensure_buf(path)
  local b = M.buffer_for(path)
  if b then
    return b
  end
  local abs = norm(path)
  vim.cmd("badd " .. vim.fn.fnameescape(abs))
  b = M.buffer_for(path)
  if b then
    vim.fn.bufload(b)
    if vim.api.nvim_buf_line_count(b) == 1 and vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == "" then
      if vim.fn.filereadable(abs) == 1 then
        vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.fn.readfile(abs))
      end
    end
  end
  return b
end

function M.apply(op)
  if type(op) ~= "table" or not op.op then
    return false, "bad op"
  end
  if op.op == "read_buffer" then
    local path = op.path
    if not path then
      return false, "no path"
    end
    if not tostring(path):match("^/") then
      path = vim.fn.getcwd() .. "/" .. path
    end
    local b = M.ensure_buf(path)
    if not b then
      return false, "no buffer"
    end
    local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
    return true, table.concat(lines, "\n")
  end

  if op.op == "replace_in_buffer" then
    local path = op.path
    if not path then
      return false, "no path"
    end
    if not tostring(path):match("^/") then
      path = vim.fn.getcwd() .. "/" .. path
    end
    local b = M.ensure_buf(path)
    if not b then
      return false, "no buffer"
    end
    local old, new = op.old_text, op.new_text
    if type(old) ~= "string" or type(new) ~= "string" then
      return false, "missing old/new"
    end
    local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
    local text = table.concat(lines, "\n")
    local idx = text:find(old, 1, true)
    if not idx then
      local loose = old:gsub("^%s+", "")
      local li = text:find(loose, 1, true)
      if li then
        local line_start = text:sub(1, li):match(".*\n()") or 1
        local line_end = text:find("\n", li, true) or (#text + 1)
        old = text:sub(line_start, line_end - 1)
        idx = line_start
        local indent = old:match("^(%s*)") or ""
        new = indent .. new:gsub("^%s+", "")
      end
    end
    if not idx then
      return false, "old_text not found"
    end
    local before = vim.deepcopy(lines)
    local replaced = text:sub(1, idx - 1) .. new .. text:sub(idx + #old)
    local new_lines = vim.split(replaced, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(b, 0, -1, false, new_lines)
    local changed_row = 1
    for i, line in ipairs(new_lines) do
      if before[i] ~= line then
        changed_row = i
        break
      end
    end
    local rel = vim.fn.fnamemodify(path, ":.")
    session.record_edit({
      path = norm(path),
      rel = rel,
      before = before,
      buf = b,
      changed_row = changed_row,
    })
    return true, "edited " .. rel
  end

  return false, "unknown op " .. tostring(op.op)
end

function M.handle_ui_request(req)
  if not req or req.method ~= "input" or req.title ~= M.HOST_TITLE then
    return nil
  end
  local okj, op = pcall(vim.json.decode, req.placeholder or "")
  if not okj then
    return { type = "extension_ui_response", id = req.id, value = "error:bad json" }
  end
  local ok, result = M.apply(op)
  return {
    type = "extension_ui_response",
    id = req.id,
    value = ok and result or ("error:" .. tostring(result)),
  }
end

return M
