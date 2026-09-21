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

-- a giant jsonl line must not be decoded (that freezes the UI)
local big = vim.fn.tempname() .. ".jsonl"
local f = io.open(big, "w")
f:write('{"type":"session","name":"cap"}\n')
f:write(string.rep("x", 20000) .. "\n")
f:write('{"type":"message","message":{"role":"user","content":"kept"}}\n')
f:close()
local msgs, truncated = sessions.load_messages(big)
h.assert_eq(#msgs, 1, "skipped giant line")
h.assert_eq(msgs[1].content, "kept", "kept small message")
h.assert_truthy(truncated, "truncated flag")
os.remove(big)

-- pages come back newest-last; the next page is older
local paged = vim.fn.tempname() .. ".jsonl"
local pf = io.open(paged, "w")
for i = 1, 5 do
  pf:write(string.format('{"type":"message","message":{"role":"user","content":"m%d"}}\n', i))
end
pf:close()
local hist = sessions.open_history(paged)
local page1, done1 = sessions.history_page(hist, 2)
h.assert_eq(#page1, 2, "first page size")
h.assert_eq(page1[1].content, "m4", "older of recent pair")
h.assert_eq(page1[2].content, "m5", "newest")
h.assert_false(done1, "more remains")
local page2 = sessions.history_page(hist, 2)
h.assert_eq(page2[1].content, "m2", "next older")
h.assert_eq(page2[2].content, "m3", "then m3")

package.loaded["pi.render"] = nil
local render = require("pi.render")
local hist2 = sessions.open_history(paged)
local recent = sessions.history_page(hist2, 2)
local buf = vim.api.nvim_create_buf(false, true)
render.setup(buf)
render.hydrate(buf, recent, { history = hist2, footer = false })
local before = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
h.assert_truthy(before:find("m5", 1, true), "recent painted")
h.assert_false(before:find("m1", 1, true), "older not yet")
h.assert_truthy(render.load_older(buf), "loaded older page")
local after = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
h.assert_truthy(after:find("m1", 1, true), "older prepended")
h.assert_truthy(after:find("m1", 1, true) < after:find("m5", 1, true), "older sits above recent")

local prefixed = vim.fn.tempname() .. ".jsonl"
local pref = io.open(prefixed, "w")
pref:write(string.rep("x", 200000) .. "\n")
for i = 1, 3 do
  pref:write(string.format('{"type":"message","message":{"role":"user","content":"p%d"}}\n', i))
end
pref:close()
local hist3 = sessions.open_history(prefixed)
local tail, tail_done = sessions.history_page(hist3, 2)
h.assert_eq(tail[1].content, "p2", "tail page skips the prefix")
h.assert_eq(tail[2].content, "p3", "newest of the tail")
h.assert_false(tail_done, "prefix still unread")
h.assert_truthy(hist3.cursor > 200000, "did not scan from the start")
os.remove(prefixed)

os.remove(paged)
