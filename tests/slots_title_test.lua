local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.slots"] = nil
package.loaded["pi.config"] = nil
require("pi.config").setup({ bootstrap = false })
local slots = require("pi.slots")

local s = {
  id = 2,
  status = "busy",
  goal = "fix auth token leak",
  activity = "bash: rg token",
  session_name = nil,
}
-- pretend primary is 1 so no focus suffix
local title = slots.format_title(s, 80)
h.assert_truthy(title:find("fix auth token leak", 1, true), "goal in title: " .. title)
h.assert_truthy(title:find("bash: rg token", 1, true), "activity in title: " .. title)
h.assert_truthy(title:find("#2", 1, true), "id in title")
h.assert_truthy(title:find("●", 1, true), "busy dot")

s.status = "idle"
s.activity = nil
title = slots.format_title(s, 80)
h.assert_truthy(title:find("○", 1, true), "idle dot")
h.assert_truthy(title:find("fix auth token leak", 1, true), "goal persists when idle")
h.assert_false(title:find("Working", 1, true), "no Working when idle")

s.goal = nil
s.session_name = "my-session"
s.status = "busy"
title = slots.format_title(s, 80)
h.assert_truthy(title:find("my-session", 1, true), "session name as goal fallback")
h.assert_truthy(title:find("Working", 1, true), "Working when busy no activity")

-- tool activity helper via on_primary_event needs a live slot — test format only above
print("OK slots_title_test")
