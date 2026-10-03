local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.render"] = nil
package.loaded["pi.runtime"] = nil
package.loaded["pi.sessions"] = nil
package.loaded["pi.session"] = nil
package.loaded["pi.client"] = nil

vim.o.columns = 120
vim.o.lines = 40

local render = require("pi.render")
local runtime = require("pi.runtime")

local buf = vim.api.nvim_create_buf(false, true)
render.setup(buf)
local win = vim.api.nvim_open_win(buf, true, {
  relative = "editor",
  width = 40,
  height = 20,
  row = 1,
  col = 1,
  style = "minimal",
  border = "single",
})

--- Non-empty body rows (excludes header + BOTTOM_PAD blanks). Total line count
--- is a poor signal: hydrate may add "# pi chat" while pad keeps +2 at EOF.
local function body_rows(b)
  local n = 0
  for _, l in ipairs(vim.api.nvim_buf_get_lines(b, 0, -1, false)) do
    if l ~= "" and not l:match("^# pi chat") then
      n = n + 1
    end
  end
  return n
end

local long = string.rep("abcdefghij ", 15)
render.append_user(buf, long)
local before = body_rows(buf)
h.assert_truthy(before > 4, "narrow wrap produces multiple lines: " .. before)
h.assert_eq(#render.transcript(buf), 1, "transcript records user")

vim.api.nvim_win_set_config(win, {
  relative = "editor",
  width = 100,
  height = 30,
  row = 1,
  col = 1,
  style = "minimal",
  border = "single",
})

-- In-memory transcript (no session / RPC)
local ok_mem = runtime.reflow_buf(buf, {
  win = win,
  footer = false,
  client = {
    is_running = function()
      return false
    end,
  },
})
h.assert_truthy(ok_mem, "reflow_buf from transcript")
local after_mem = body_rows(buf)
h.assert_truthy(after_mem < before, string.format("transcript reflow fewer body rows (%d → %d)", before, after_mem))

-- Disk path when transcript empty
local path = vim.fn.tempname() .. ".jsonl"
local f = assert(io.open(path, "w"))
f:write(vim.json.encode({
  type = "message",
  message = { role = "user", content = long },
}) .. "\n")
f:close()

local tbuf = vim.api.nvim_create_buf(false, true)
render.setup(tbuf)
local twin = vim.api.nvim_open_win(tbuf, true, {
  relative = "editor",
  width = 40,
  height = 10,
  row = 2,
  col = 2,
  style = "minimal",
  border = "single",
})
-- Paint without recording via hydrate, then clear transcript to force disk
render.hydrate(tbuf, { { role = "user", content = long } }, { footer = false })
local before2 = #vim.api.nvim_buf_get_lines(tbuf, 0, -1, false)
-- wipe transcript mirror only
package.loaded["pi.render"] = nil -- keep same module; clear via reset+no store
-- Directly clear by reset then repaint lines without transcript: use hydrate skip
-- Easiest: reset clears transcript; re-hydrate from disk via reflow_buf
render.reset(tbuf)
h.assert_eq(#render.transcript(tbuf), 0, "reset clears transcript")
vim.api.nvim_win_set_config(twin, {
  relative = "editor",
  width = 100,
  height = 20,
  row = 2,
  col = 2,
  style = "minimal",
  border = "single",
})
h.assert_truthy(
  runtime.reflow_buf(tbuf, {
    win = twin,
    footer = false,
    session_file = path,
    client = {
      is_running = function()
        return false
      end,
    },
  }),
  "reflow_buf from disk"
)
local after2 = #vim.api.nvim_buf_get_lines(tbuf, 0, -1, false)
h.assert_truthy(after2 > 0, "disk reflow painted")
h.assert_truthy(after2 <= before2, "disk reflow at wide width")

os.remove(path)
print("OK reflow_maximize_test")
