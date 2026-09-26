-- Top-right float for compaction status (mirrors core.readonly indicator style).
-- compacting → " C… " ; auto-compaction on (idle) → " AC "
local M = {}

M.floating_win = nil
M.floating_buf = nil

local function close()
  if M.floating_win and vim.api.nvim_win_is_valid(M.floating_win) then
    pcall(vim.api.nvim_win_close, M.floating_win, true)
  end
  M.floating_win = nil
  if M.floating_buf and vim.api.nvim_buf_is_valid(M.floating_buf) then
    pcall(vim.api.nvim_buf_delete, M.floating_buf, { force = true })
  end
  M.floating_buf = nil
end

local function ensure_hl()
  if vim.fn.hlexists("PiCompactFloat") == 0 then
    vim.api.nvim_set_hl(0, "PiCompactFloat", { fg = 0xe0af68, bold = true })
  end
end

---Refresh float from session flags.
---@param opts { compacting?: boolean, auto?: boolean|nil }|nil
function M.update(opts)
  opts = opts or {}
  local compacting = opts.compacting
  local auto = opts.auto
  if compacting == nil or auto == nil then
    local ok, session = pcall(require, "pi.session")
    if ok then
      local st = session.get()
      if compacting == nil then
        compacting = st.status == "compacting"
      end
      if auto == nil then
        auto = st.auto_compaction
      end
    end
  end

  local text ---@type string|nil
  local hl = "PiCompactFloat"
  if compacting then
    text = " C… "
  elseif auto == true then
    text = " AC "
  else
    close()
    return
  end

  ensure_hl()
  close()

  M.floating_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(M.floating_buf, 0, -1, false, { text })
  vim.bo[M.floating_buf].buftype = "nofile"
  vim.bo[M.floating_buf].bufhidden = "wipe"
  vim.bo[M.floating_buf].modifiable = false
  vim.bo[M.floating_buf].readonly = true
  vim.api.nvim_buf_add_highlight(M.floating_buf, -1, hl, 0, 0, -1)

  local width = vim.fn.strdisplaywidth(text)
  -- Sit left of readonly " R " (width 3) with a small gap
  local col = math.max(0, vim.o.columns - width - 1 - 5)
  M.floating_win = vim.api.nvim_open_win(M.floating_buf, false, {
    relative = "editor",
    width = width,
    height = 1,
    row = 1,
    col = col,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 50,
  })
  vim.wo[M.floating_win].winhl = "Normal:PiCompactFloat,NormalNC:PiCompactFloat"
  vim.wo[M.floating_win].winblend = 20
end

function M.refresh()
  M.update()
end

function M.hide()
  close()
end

return M
