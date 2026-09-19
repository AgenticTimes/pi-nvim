local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.sessions"] = nil
local sessions = require("pi.sessions")

-- encoding matches pi getDefaultSessionDirPath
local dir = sessions.session_dir_for("/Users/meetai/source/pi")
h.assert_truthy(dir:match("%-%-Users%-meetai%-source%-pi%-%-$"), "encode path: " .. dir)

local dir2 = sessions.session_dir_for("/Users/meetai")
h.assert_truthy(dir2:match("%-%-Users%-meetai%-%-$"), "encode home: " .. dir2)

-- list returns table (may be empty for nvim cwd)
local items = sessions.list("/Users/meetai")
h.assert_truthy(type(items) == "table", "list table")
if #items > 0 then
  h.assert_truthy(items[1].path:match("%.jsonl$"), "jsonl path")
  h.assert_truthy(items[1].label and #items[1].label > 0, "label")
  local latest = sessions.latest("/Users/meetai")
  h.assert_eq(latest.path, items[1].path, "latest is newest")
end

-- empty cwd → nil latest
local empty = sessions.latest("/tmp/pi-nvim-no-such-project-xyz")
h.assert_eq(empty, nil, "latest nil when none")

-- load_messages from a real nvim config session if present
local nvim_items = sessions.list(vim.fn.expand("~/.config/nvim"))
if #nvim_items > 0 then
  local msgs = sessions.load_messages(nvim_items[1].path)
  h.assert_truthy(#msgs > 0, "load_messages non-empty")
  h.assert_truthy(msgs[1].role == "user" or msgs[1].role == "assistant", "role")
end
