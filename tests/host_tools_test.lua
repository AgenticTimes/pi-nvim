local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path
vim.cmd("cd " .. vim.fn.fnameescape(h.root))

require("pi.session").reset()
local host = require("pi.host_tools")

local path = h.root .. "/demo/sample.lua"
vim.fn.writefile({
  "local M = {}",
  'function M.x() return "hello" end',
  "return M",
}, path)
vim.cmd("edit! " .. vim.fn.fnameescape(path))

local ok, msg = host.apply({
  op = "replace_in_buffer",
  path = path,
  old_text = 'return "hello"',
  new_text = 'return "world"',
})
h.assert_truthy(ok, msg)
local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
h.assert_truthy(text:find("world", 1, true), "replaced")
h.assert_eq(#require("pi.session").touched(), 1, "recorded")
