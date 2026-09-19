local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.render"] = nil
local render = require("pi.render")

-- message_text: text + toolCalls
local t = render.message_text({
  { type = "thinking", thinking = "secret" },
  { type = "text", text = "hello" },
  { type = "toolCall", name = "nvim_read_buffer" },
  { type = "toolCall", name = "nvim_open" },
})
h.assert_truthy(t:find("hello", 1, true), "keeps text")
h.assert_truthy(t:find("2 tool call", 1, true), "counts tools")
h.assert_false(t:find("secret", 1, true), "skips thinking")

-- normalize_messages skips toolResult
local msgs = render.normalize_messages({
  messages = {
    { role = "user", content = { { type = "text", text = "hi" } } },
    { role = "toolResult", content = { { type = "text", text = "noise" } } },
    { role = "assistant", content = "ok" },
    { message = { role = "user", content = "nested" } },
  },
})
h.assert_eq(#msgs, 3, "user+assistant+nested user")
h.assert_eq(msgs[1].role, "user", "role1")
h.assert_eq(msgs[2].role, "assistant", "role2")

-- hydrate paints chat
local b = vim.api.nvim_create_buf(false, true)
render.setup(b)
local n = render.hydrate(b, msgs, { footer = "· resumed session" })
h.assert_eq(n, 3, "three messages hydrated")
local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
local joined = table.concat(lines, "\n")
h.assert_truthy(joined:find("### you", 1, true), "you header")
h.assert_truthy(joined:find("### assistant", 1, true), "assistant header")
h.assert_truthy(joined:find("· resumed session", 1, true), "footer")
h.assert_false(joined:find("noise", 1, true), "no toolResult body")

-- resume_last default
package.loaded["pi.config"] = nil
local config = require("pi.config")
h.assert_eq(config.opts.resume_last, true, "resume_last default on")
