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

return M
