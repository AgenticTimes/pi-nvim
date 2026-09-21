local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.todos"] = nil
local todos = require("pi.todos")

local dir = vim.fn.tempname() .. "-todos"
vim.fn.mkdir(dir, "p")

local function write_todo(name, obj)
  local body = vim.json.encode(obj) .. "\n\nnotes\n"
  vim.fn.writefile(vim.split(body, "\n", { plain = true }), dir .. "/" .. name)
end

write_todo("aaaa1111.md", {
  id = "aaaa1111",
  title = "open task",
  status = "open",
  created_at = "2026-01-01T00:00:00.000Z",
})
write_todo("bbbb2222.md", {
  id = "bbbb2222",
  title = "claimed task",
  status = "open",
  created_at = "2026-01-02T00:00:00.000Z",
  assigned_to_session = "sess",
})
write_todo("cccc3333.md", {
  id = "cccc3333",
  title = "finished",
  status = "closed",
  created_at = "2026-01-03T00:00:00.000Z",
})
write_todo("dddd4444.md", {
  id = "dddd4444",
  title = "done task",
  status = "done",
  created_at = "2026-01-04T00:00:00.000Z",
})

local list = todos.list_dir(dir)
h.assert_eq(#list, 2, "open only")
h.assert_eq(list[1].title, "claimed task", "claimed first")
h.assert_eq(list[2].title, "open task", "then open")

local lines = todos.lines(list)
local joined = table.concat(lines, "\n")
h.assert_truthy(joined:find("claimed task", 1, true), "shows claimed")
h.assert_truthy(joined:find("open task", 1, true), "shows open")
h.assert_false(joined:find("finished", 1, true), "hides closed")
h.assert_false(joined:find("done task", 1, true), "hides done")

vim.fn.delete(dir, "rf")
