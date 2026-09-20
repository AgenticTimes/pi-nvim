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
h.assert_truthy(t:find("secret", 1, true), "includes thinking")
h.assert_false(t:find("### thinking", 1, true), "no thinking header")

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
h.assert_truthy(joined:find("hi", 1, true), "user text")
h.assert_truthy(joined:find("ok", 1, true), "assistant text")
h.assert_false(joined:find("### you", 1, true), "no you header")
h.assert_false(joined:find("### assistant", 1, true), "no assistant header")
h.assert_truthy(joined:find("· resumed session", 1, true), "footer")
h.assert_false(joined:find("noise", 1, true), "no toolResult body")

-- user bubble has blue bar + box + bg (box chrome lives in its own namespace)
local marks = h.box_marks(b)
local has_bar = false
local has_bubble = false
local has_box = false
for _, m in ipairs(marks) do
  local d = m[4] or {}
  if d.sign_hl_group == "PiYouBar" or d.sign_text == "▌" then
    has_bar = true
  end
  if d.line_hl_group == "PiYouBubble" then
    has_bubble = true
  end
  if d.virt_lines then
    local chunk = d.virt_lines[1] and d.virt_lines[1][1]
    if chunk and (tostring(chunk[1]):find("╭", 1, true) or tostring(chunk[1]):find("╰", 1, true)) then
      has_box = true
    end
  end
  if d.virt_text then
    for _, vt in ipairs(d.virt_text) do
      if vt[2] == "PiYouBorder" then
        has_box = true
      end
    end
  end
end
h.assert_truthy(has_bar, "user blue bar")
h.assert_truthy(has_bubble, "user bubble bg")
h.assert_truthy(has_box, "user box border")

-- each role gets its own box style: user=blue rounded, tool=violet square, thinking=gray dashed
local roles = vim.api.nvim_create_buf(false, true)
render.setup(roles)
render.hydrate(roles, {
  { role = "user", content = { { type = "text", text = "ask" } } },
  {
    role = "assistant",
    content = {
      { type = "thinking", thinking = "pondering" },
      { type = "toolCall", name = "nvim_read_buffer" },
      { type = "text", text = "done" },
    },
  },
}, { footer = false })
local rmarks = h.box_marks(roles)
local boxes = {}
for _, m in ipairs(rmarks) do
  local d = m[4] or {}
  if d.sign_hl_group then
    boxes[d.sign_hl_group] = boxes[d.sign_hl_group] or { lines = {} }
    local e = boxes[d.sign_hl_group]
    e.lines[m[2]] = true
    e.bar = d.sign_text
    e.border = nil
    for _, vt in ipairs(d.virt_text or {}) do
      if vt[2] ~= d.sign_hl_group then
        e.border = vt[2]
      end
    end
  end
end
for _, hl in ipairs({ "PiToolBar", "PiThinkBar" }) do
  h.assert_truthy(boxes[hl], "missing box for " .. hl)
end
h.assert_eq(vim.trim(boxes["PiThinkBar"].bar), "▏", "thinking uses its own left bar glyph")
h.assert_truthy(boxes["PiThinkBar"].border == "PiThinkBorder", "thinking border hl")
h.assert_truthy(boxes["PiToolBar"].border == "PiToolBorder", "tool border hl")
-- thinking glyph set differs from tool glyph set
local saw_dashed, saw_square = false, false
local label_of = { PiYouBar = "user", PiToolBar = "toolcall", PiThinkBar = "thinking" }
local label_seen = {}
for _, box in ipairs(h.box_namespaces()) do
  local role, top, top_chunks
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(roles, box.ns, 0, -1, { details = true })) do
    local d = m[4] or {}
    if d.sign_hl_group then
      role = d.sign_hl_group
    end
    if d.virt_lines and d.virt_lines_above then
      top_chunks = d.virt_lines[1]
      top = ""
      for _, chunk in ipairs(top_chunks) do
        top = top .. tostring(chunk[1])
      end
    end
    if top and top:find("┄", 1, true) then
      saw_dashed = true
    end
    if top and top:find("┌", 1, true) then
      saw_square = true
    end
  end
  if role and top and label_of[role] then
    label_seen[role] = true
    h.assert_truthy(top:find(label_of[role], 1, true) ~= nil, role .. " label in the top rule: " .. top)
    -- the label must not push the corner off the box edge
    h.assert_eq(vim.fn.strdisplaywidth(top), vim.o.columns, "label keeps the box width: " .. top)
    -- and it is its own chunk so it can carry its own highlight
    local own = false
    for _, chunk in ipairs(top_chunks) do
      if chunk[1] == label_of[role] then
        own = true
        h.assert_truthy(chunk[2] ~= nil, "label chunk has its own hl")
      end
    end
    h.assert_truthy(own, "label is a separate virt_line chunk")
  end
end
h.assert_truthy(label_seen.PiYouBar and label_seen.PiToolBar and label_seen.PiThinkBar, "every role box is labelled")
h.assert_truthy(saw_dashed, "thinking box uses dashed horizontal rule")
h.assert_truthy(saw_square, "tool box uses square corners")

-- resume_last default
package.loaded["pi.config"] = nil
local config = require("pi.config")
h.assert_eq(config.opts.resume_last, true, "resume_last default on")
