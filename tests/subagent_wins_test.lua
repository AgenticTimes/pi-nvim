local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.ui"] = {
  chat_buf = function()
    return vim.api.nvim_create_buf(false, true)
  end,
  chat_win = function()
    return nil
  end,
  is_open = function()
    return false
  end,
  open = function() end,
  adopt_chat_buf = function() end,
  adopt_chat_win = function() end,
  open_input = function() end,
  refresh_title = function() end,
}
package.loaded["pi.render"] = {
  attach_scroll = function() end,
  setup = function() end,
  reset = function() end,
  follow = function() end,
  toggle_tool_at_cursor = function()
    return false
  end,
  toggle_fold_kind = function() end,
  jump_message = function() end,
  on_event = function() end,
}
package.loaded["pi.compact_indicator"] = { hide = function() end }
package.loaded["pi.statusline"] = { repaint = function() end }
package.loaded["pi.session"] = {
  get = function()
    return {}
  end,
}
package.loaded["pi.client"] = {
  is_running = function()
    return true
  end,
  start = function() end,
  stop = function() end,
  send = function() end,
  set_on_event = function() end,
  new = function()
    return package.loaded["pi.client"]
  end,
}
package.loaded["pi.runtime"] = {
  bind_events = function() end,
  start_job = function() end,
}
package.loaded["pi.config"] = nil
package.loaded["pi.slots"] = nil
package.loaded["pi.subagent_wins"] = nil

require("pi.config").setup({
  subagent_windows = true,
  window = { width = 1, height = 1, layout = "float" },
})

-- Fake large enough UI geometry via o
vim.o.columns = 200
vim.o.lines = 60

local slots = require("pi.slots")
slots._reset_for_test()
slots.ensure_default()

local sw = require("pi.subagent_wins")
sw._reset_for_test()

local handled = sw.handle({
  v = 1,
  op = "started",
  runId = "run-1",
  agent = "scout",
  goal = "say hi",
})
h.assert_truthy(handled, "started handled")
h.assert_eq(slots.count(), 2, "viewer + default")

local title = ""
for _, s in ipairs(slots.live()) do
  if s.is_viewer then
    title = slots.format_title(s, 80)
    h.assert_eq(s.status, "busy", "viewer busy")
    h.assert_eq(s.run_id, "run-1", "run id")
  end
end
h.assert_truthy(title:find("scout", 1, true) or title:find("◇", 1, true), "viewer title: " .. title)

sw.handle({
  op = "complete",
  runId = "run-1",
  success = true,
  summary = "hi",
})
for _, s in ipairs(slots.live()) do
  if s.is_viewer then
    h.assert_eq(s.status, "idle", "viewer idle after complete")
  end
end

-- Unknown agent: no permanent viewer spam
local before = slots.count()
sw.handle({
  op = "complete",
  runId = "bad-1",
  success = false,
  failedFast = true,
  summary = "Unknown agent: general-purpose\nEffective cwd: /tmp",
})
h.assert_eq(slots.count(), before, "no viewer for unknown agent")

-- Async detach text must NOT finalize
sw.handle({
  op = "started",
  runId = "async-1",
  agent = "worker",
  goal = "hello",
})
sw.handle({
  op = "complete",
  runId = "async-1",
  success = true,
  summary = "The async run is detached and running in the background.\nnative completion notification",
})
for _, s in ipairs(slots.live()) do
  if s.run_id == "async-1" then
    h.assert_eq(s.status, "busy", "detach receipt keeps busy")
  end
end

-- Prefer output-*.log when asyncDir present
local sample = vim.fn.glob(
  "/var/folders/*/T/pi-subagents-uid-*/async-subagent-runs/*/status.json",
  true,
  true
)
if type(sample) == "table" and sample[1] then
  local dir = vim.fn.fnamemodify(sample[1], ":h")
  local rid = vim.fn.fnamemodify(dir, ":t")
  sw.handle({
    op = "started",
    runId = rid,
    agent = "worker",
    asyncDir = dir,
  })
  local s = nil
  for _, slot in ipairs(slots.live()) do
    if slot.run_id == rid then
      s = slot
    end
  end
  h.assert_truthy(s, "sample viewer")
  local lines = vim.api.nvim_buf_get_lines(s.chat_buf, 0, -1, false)
  local body = table.concat(lines, "\n")
  h.assert_false(body:find('"lifecycleArtifactVersion"', 1, true), "no raw status.json dump")
  h.assert_truthy(body:find("hello,world", 1, true) or body:find("waiting for output", 1, true), "output or waiting")
end

-- UI request path
local ok = sw.handle_ui_request({
  method = "setWidget",
  widgetKey = "__nvim_subagent__",
  widgetLines = {
    vim.json.encode({
      v = 1,
      op = "started",
      runId = "run-2",
      agent = "reviewer",
      goal = "review",
    }),
  },
})
h.assert_truthy(ok, "ui request ok")
vim.wait(50, function()
  return slots.count() >= 3
end, 5)
h.assert_truthy(slots.count() >= 3, "second viewer")

-- bridge in build_cmd
package.loaded["pi.runtime"] = nil
package.loaded["pi.config"] = nil
local started = {}
package.loaded["pi.client"] = {
  is_running = function()
    return false
  end,
  start = function(opts)
    table.insert(started, opts.cmd)
  end,
  set_on_event = function() end,
  send = function() end,
  stop = function() end,
}
package.loaded["pi.events"] = { fire = function() end }
package.loaded["pi.approve"] = {
  handle = function()
    return false
  end,
}
package.loaded["pi.host_tools"] = { handle_ui_request = function() end }
package.loaded["pi.review"] = { auto_show = function() end }
package.loaded["pi.slash"] = { invalidate = function() end }
package.loaded["pi.ui"] = {
  on_event = function() end,
  refresh_title = function() end,
  chat_buf = function()
    return 1
  end,
}
require("pi.config").setup({
  subagent_windows = true,
  extensions = { "~/.pi/agent/npm/node_modules/pi-subagents" },
})
local runtime = require("pi.runtime")
-- ensure_started needs more stubs
package.loaded["pi.slots"] = {
  primary_client = function()
    return nil
  end,
  ensure_default = function() end,
  on_primary_event = function() end,
}
runtime.ensure_started()
local cmd = table.concat(started[#started] or {}, " ")
h.assert_truthy(cmd:find("nvim_subagent_bridge", 1, true), "bridge -e: " .. cmd)
h.assert_truthy(cmd:find("pi-subagents", 1, true), "subagents -e: " .. cmd)

print("subagent_wins_test ok")
