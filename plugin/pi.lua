if vim.g.loaded_pi_nvim then
  return
end
vim.g.loaded_pi_nvim = true

vim.api.nvim_create_user_command("Pi", function()
  require("pi").toggle()
end, { desc = "Toggle pi.nvim UI" })

vim.api.nvim_create_user_command("PiStop", function()
  require("pi").stop()
end, { desc = "Abort pi agent" })

vim.api.nvim_create_user_command("PiInterrupt", function()
  require("pi").interrupt()
end, { desc = "Interrupt in-flight LLM request" })

vim.api.nvim_create_user_command("PiCompact", function(opts)
  local instr = opts.args
  if instr == "" then
    require("pi").compact()
  else
    require("pi").compact({ custom_instructions = instr })
  end
end, { nargs = "*", desc = "Compact pi session context" })

vim.api.nvim_create_user_command("PiAutoCompact", function()
  require("pi").toggle_auto_compaction()
end, { desc = "Toggle pi auto-compaction" })

vim.api.nvim_create_user_command("PiNewSession", function()
  require("pi.runtime").new_session()
end, { desc = "Start new pi session" })

vim.api.nvim_create_user_command("PiDiff", function()
  require("pi.review").open(1)
end, { desc = "Open pi review diff" })

vim.api.nvim_create_user_command("PiAccept", function()
  require("pi").accept()
end, { desc = "Accept current pending edit" })

vim.api.nvim_create_user_command("PiReject", function()
  require("pi").reject()
end, { desc = "Reject current pending edit" })

vim.api.nvim_create_user_command("PiCycleModel", function()
  require("pi.runtime").cycle_model()
end, { desc = "Cycle pi model" })

vim.api.nvim_create_user_command("PiPickModel", function()
  require("pi.runtime").pick_model()
end, { desc = "Pick pi model" })

vim.api.nvim_create_user_command("PiCycleThinking", function()
  require("pi.runtime").cycle_thinking()
end, { desc = "Cycle pi thinking level" })

vim.api.nvim_create_user_command("PiPickThinking", function()
  require("pi.runtime").pick_thinking()
end, { desc = "Pick pi thinking level" })

vim.api.nvim_create_user_command("PiFullscreen", function()
  require("pi.ui").toggle_fullscreen()
end, { desc = "Toggle pi fullscreen UI" })

vim.api.nvim_create_user_command("PiSessions", function()
  require("pi.sessions").pick()
end, { desc = "Pick a pi session for this cwd" })

vim.api.nvim_create_user_command("PiRun", function(opts)
  local msg = opts.args
  if msg == "" then
    vim.notify("PiRun: message required", vim.log.levels.WARN)
    return
  end
  require("pi.runtime").run(msg)
end, { nargs = "+", desc = "Open pi UI and prompt" })

vim.api.nvim_create_user_command("PiAcceptAll", function()
  require("pi.review").accept_all()
end, { desc = "Accept all pending pi edits" })

vim.api.nvim_create_user_command("PiRejectAll", function()
  require("pi.review").reject_all()
end, { desc = "Reject all pending pi edits" })

vim.api.nvim_create_user_command("PiSlash", function()
  require("pi.slash").insert_into(require("pi.ui").input_buf())
end, { desc = "Pick a pi slash command" })

vim.api.nvim_create_user_command("PiSkills", function()
  require("pi.skills").insert_into(require("pi.ui").input_buf())
end, { desc = "Pick a pi skill" })

vim.api.nvim_create_user_command("PiExportHtml", function(opts)
  require("pi.runtime").export_html(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Export pi session to HTML", complete = "file" })

vim.api.nvim_create_user_command("PiMode", function(opts)
  local m = opts.args
  if m == "" then
    require("pi.runtime").toggle_mode()
  else
    require("pi.runtime").set_mode(m)
  end
end, { nargs = "?", complete = function()
  return { "chat", "auto" }
end, desc = "Toggle or set pi mode (chat|auto)" })

vim.api.nvim_create_user_command("PiFocus", function()
  require("pi.ui").focus_toggle()
end, { desc = "Toggle focus pi ↔ editor" })

vim.api.nvim_create_user_command("PiName", function(opts)
  require("pi.runtime").set_session_name(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Set pi session name" })

vim.api.nvim_create_user_command("PiInspect", function(opts)
  local kind = opts.args
  local insp = require("pi.inspect")
  if kind == "state" then
    insp.show_state()
  elseif kind == "messages" then
    insp.show_messages()
  elseif kind == "entries" then
    insp.show_entries()
  else
    insp.pick()
  end
end, {
  nargs = "?",
  complete = function()
    return { "state", "messages", "entries" }
  end,
  desc = "Inspect pi session JSON",
})

vim.api.nvim_create_user_command("PiApprove", function(opts)
  local m = opts.args
  if m == "" then
    require("pi.approve").cycle_mode()
  else
    require("pi.approve").set_mode(m)
  end
end, {
  nargs = "?",
  complete = function()
    return { "ask", "smart", "auto", "deny" }
  end,
  desc = "Cycle or set pi approve mode",
})

vim.api.nvim_create_user_command("PiToggleIdle", function()
  require("pi.slots").toggle_idle()
end, { desc = "Hide or show all idle (not working) slot windows" })

vim.api.nvim_create_user_command("PiSlot", function(opts)
  local n = tonumber(opts.args)
  if not n then
    vim.notify("pi: usage :PiSlot {id}", vim.log.levels.WARN)
    return
  end
  require("pi.slots").focus_by_id(n)
end, { nargs = 1, desc = "Promote slot #id to master window" })
