local M = {}

function M.setup(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = true
end

function M.reset(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# pi chat", "" })
end

function M.append(buf, line)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { line })
end

function M.on_event(buf, ev)
  if ev.type == "tool_execution_start" then
    M.append(buf, string.format("⚙ tool `%s`", tostring(ev.toolName)))
  elseif ev.type == "tool_execution_end" then
    M.append(buf, string.format("⚙ end `%s` err=%s", tostring(ev.toolName), tostring(ev.isError)))
  elseif ev.type == "agent_start" then
    M.append(buf, "— agent start —")
  elseif ev.type == "agent_end" then
    M.append(buf, "— agent end —")
  elseif ev.type == "message_update" and ev.assistantMessageEvent then
    local a = ev.assistantMessageEvent
    if a.type == "text_delta" and a.delta then
      -- append delta to last line if streaming; simple: new chunk lines
      local lines = vim.api.nvim_buf_get_lines(buf, -2, -1, false)
      local last = lines[1] or ""
      if last:match("^—") or last:match("^⚙") or last:match("^#") or last == "" then
        M.append(buf, a.delta)
      else
        vim.api.nvim_buf_set_lines(buf, -2, -1, false, { last .. a.delta })
      end
    end
  end
end

return M
