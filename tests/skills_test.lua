local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.slash"] = {
  fetch = function()
    return {
      { name = "compact", description = "c", source = "builtin" },
      { name = "skill:brave-search", description = "search", source = "skill" },
      { name = "skill:git", description = "git", source = "skill" },
    }
  end,
  invalidate = function() end,
}
package.loaded["pi.skills"] = nil
local skills = require("pi.skills")
local list = skills.list()
h.assert_eq(#list, 2, "two skills")
h.assert_eq(list[1].name, "skill:brave-search", "first skill")

package.loaded["pi.slash"] = nil
package.loaded["pi.skills"] = nil
