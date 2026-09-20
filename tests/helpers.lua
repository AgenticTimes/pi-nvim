-- Test helpers for pi.nvim headless suite
local M = {}

M.root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

function M.assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. string.format(": expected %s, got %s", vim.inspect(b), vim.inspect(a)), 2)
  end
end

function M.assert_truthy(v, msg)
  if not v then
    error(msg or "assert_truthy failed", 2)
  end
end

function M.assert_false(v, msg)
  if v then
    error(msg or "assert_false failed", 2)
  end
end

--- Box-chrome namespaces (`pi_box_<n>`), oldest first
function M.box_namespaces()
  local out = {}
  for name, id in pairs(vim.api.nvim_get_namespaces()) do
    local seq = tostring(name):match("^pi_box_(%d+)$")
    if seq then
      out[#out + 1] = { ns = id, seq = tonumber(seq) }
    end
  end
  table.sort(out, function(a, b)
    return a.seq < b.seq
  end)
  return out
end

--- Newest box namespace that has marks in `buf`, i.e. the box most recently painted there
function M.last_box_ns(buf)
  local list = M.box_namespaces()
  for i = #list, 1, -1 do
    local marks = vim.api.nvim_buf_get_extmarks(buf, list[i].ns, 0, -1, { limit = 1 })
    if #marks > 0 then
      return list[i].ns
    end
  end
  return nil
end

--- All box-chrome extmarks in a buffer; pass a namespace to scope to one box
function M.box_marks(buf, ns)
  local out = {}
  for _, b in ipairs(M.box_namespaces()) do
    if not ns or ns == b.ns then
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, b.ns, 0, -1, { details = true })) do
        out[#out + 1] = m
      end
    end
  end
  return out
end

return M
