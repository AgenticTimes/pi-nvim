-- Run all tests/*_test.lua under headless nvim:
--   nvim -u NONE -l tests/run.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local failed = 0
local passed = 0
local files = vim.fn.glob(root .. "/tests/*_test.lua", false, true)
table.sort(files)

for _, f in ipairs(files) do
  local name = vim.fn.fnamemodify(f, ":t")
  local ok, err = pcall(dofile, f)
  if ok then
    passed = passed + 1
    io.write("PASS " .. name .. "\n")
  else
    failed = failed + 1
    io.write("FAIL " .. name .. "\n  " .. tostring(err) .. "\n")
  end
end

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
if failed > 0 then
  os.exit(1)
end
os.exit(0)
