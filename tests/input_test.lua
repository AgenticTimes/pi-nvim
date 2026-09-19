local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

local prompted = {}
package.loaded["pi.runtime"] = {
  ensure_started = function() end,
  prompt = function(msg, opts)
    table.insert(prompted, { msg = msg, opts = opts or {} })
  end,
  abort = function() end,
}
package.loaded["pi.session"] = {
  is_busy = function()
    return false
  end,
}
package.loaded["pi.context"] = {
  expand = function(t)
    return t
  end,
  preamble = function()
    return ""
  end,
  pick_file = function() end,
}
package.loaded["pi.render"] = {
  append = function() end,
}
package.loaded["pi.ui"] = {
  chat_buf = function()
    return nil
  end,
}

package.loaded["pi.input"] = nil
package.loaded["pi.config"] = nil
require("pi.config").setup({})

local input = require("pi.input")
local b = vim.api.nvim_create_buf(false, true)
input.setup(b)

vim.api.nvim_buf_set_lines(b, 0, -1, false, { "first prompt" })
input.submit()
h.assert_eq(#input.history(), 1, "hist len 1")
h.assert_eq(input.history()[1], "first prompt", "hist[1]")
h.assert_eq(#prompted, 1, "prompted once")

vim.api.nvim_buf_set_lines(b, 0, -1, false, { "second" })
input.submit()
h.assert_eq(#input.history(), 2, "hist len 2")

input.history_prev()
local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
h.assert_eq(table.concat(lines, "\n"), "second", "prev -> second")

input.history_prev()
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
h.assert_eq(table.concat(lines, "\n"), "first prompt", "prev -> first")

input.history_next()
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
h.assert_eq(table.concat(lines, "\n"), "second", "next -> second")

input.history_next()
lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
h.assert_eq(table.concat(lines, "\n"), "", "next past end clears")

-- force steer via submit opts
prompted = {}
vim.api.nvim_buf_set_lines(b, 0, -1, false, { "redirect" })
input.submit({ streamingBehavior = "steer" })
h.assert_eq(prompted[1].opts.streamingBehavior, "steer", "submit steer opt")

-- unstub so later tests get real modules
package.loaded["pi.runtime"] = nil
package.loaded["pi.session"] = nil
package.loaded["pi.context"] = nil
package.loaded["pi.render"] = nil
package.loaded["pi.ui"] = nil
package.loaded["pi.input"] = nil
