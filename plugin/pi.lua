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
