local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

local requested = {}
package.loaded["pi.runtime"] = {
  ensure_started = function() end,
}
package.loaded["pi.client"] = {
  request = function(obj)
    table.insert(requested, obj)
    return {
      success = true,
      data = {
        commands = {
          { name = "compact", description = "Compact", source = "builtin" },
          { name = "fix-tests", description = "Fix tests", source = "prompt" },
        },
      },
    }
  end,
}
package.loaded["pi.config"] = nil
require("pi.config").setup({ rpc_timeout = 1 })

package.loaded["pi.slash"] = nil
local slash = require("pi.slash")
local cmds = slash.fetch(true)
h.assert_eq(#cmds, 2, "two commands")
h.assert_eq(cmds[1].name, "compact", "first name")
h.assert_eq(requested[1].type, "get_commands", "rpc type")

-- cache hit
requested = {}
slash.fetch()
h.assert_eq(#requested, 0, "cached")

slash.invalidate()
slash.fetch(true)
h.assert_eq(#requested, 1, "refetch after invalidate")

package.loaded["pi.runtime"] = nil
package.loaded["pi.client"] = nil
package.loaded["pi.slash"] = nil
