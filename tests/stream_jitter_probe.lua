-- Reproduce stream follow topline jitter: does topline ever decrease mid-stream?
local h = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
vim.opt.runtimepath:prepend(h.root)
package.path = h.root .. "/lua/?.lua;" .. h.root .. "/lua/?/init.lua;" .. package.path

package.loaded["pi.render"] = nil
package.loaded["pi.config"] = nil
require("pi.config").setup({ bootstrap = false, auto_fold = true, show_thinking = true })
local render = require("pi.render")

local b = vim.api.nvim_create_buf(false, true)
-- Visible window so follow/winrestview actually run
vim.cmd("enew")
local win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(win, b)
vim.api.nvim_win_set_height(win, 20)
vim.o.lines = 30
vim.o.columns = 80
vim.wo[win].wrap = true
vim.wo[win].linebreak = true
vim.wo[win].breakindent = true
vim.wo[win].smoothscroll = false
vim.wo[win].scrolloff = 0

render.setup(b)
render.reset(b)
render.attach_scroll(win, b)

local function topline()
  return vim.api.nvim_win_call(win, function()
    return vim.fn.winsaveview().topline
  end)
end

-- Start assistant stream
render.on_event(b, {
  type = "message_update",
  assistantMessageEvent = { type = "text_delta", delta = "start " },
})
-- Drain follow timer
vim.wait(50)

local samples = {}
local dips = {}
local prev = topline()
samples[#samples + 1] = { i = 0, top = prev, lines = vim.api.nvim_buf_line_count(b) }

-- Stream many chunks until content exceeds window (force follow scroll)
local words = {
  "hello ", "world ", "this ", "is ", "a ", "longer ", "streaming ", "sentence ",
  "that ", "will ", "eventually ", "wrap ", "across ", "multiple ", "buffer ",
  "lines ", "inside ", "the ", "assistant ", "bubble ", "box ", "chrome ",
}
for i = 1, 400 do
  local w = words[((i - 1) % #words) + 1]
  render.on_event(b, {
    type = "message_update",
    assistantMessageEvent = { type = "text_delta", delta = w },
  })
  if i % 2 == 0 then
    vim.wait(35)
    local top = topline()
    local n = vim.api.nvim_buf_line_count(b)
    local d = top - prev
    samples[#samples + 1] = { i = i, top = top, lines = n, d = d }
    if d < 0 then
      dips[#dips + 1] = samples[#samples]
    end
    prev = top
  end
end
vim.wait(50)
local last_top = topline()
samples[#samples + 1] = { i = 999, top = last_top, lines = vim.api.nvim_buf_line_count(b) }

print(string.format(
  "samples=%d dips=%d final_top=%d lines=%d max_top=%d",
  #samples,
  #dips,
  last_top,
  samples[#samples].lines,
  (function()
    local m = 0
    for _, s in ipairs(samples) do
      if s.top > m then
        m = s.top
      end
    end
    return m
  end)()
))
for _, s in ipairs(dips) do
  print(string.format("DIP i=%d top=%d d=%d lines=%d", s.i, s.top, s.d, s.lines))
end
-- print around first time topline grows
local printed = 0
for _, s in ipairs(samples) do
  if s.top > 1 and printed < 10 then
    print(string.format("scroll i=%d top=%d d=%s lines=%d", s.i, s.top, tostring(s.d), s.lines))
    printed = printed + 1
  end
end

if #dips > 0 then
  error("topline dipped " .. #dips .. " times during stream (downward jitter)")
end
if last_top <= 1 then
  error("stream never filled the window; probe inconclusive")
end
print("OK stream_jitter_probe")
