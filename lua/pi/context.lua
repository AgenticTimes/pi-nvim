local M = {}

local function selection_text()
  local mode = vim.fn.mode()
  -- Active visual selection (getregion on nvim ≥ 0.10)
  if mode == "v" or mode == "V" or mode == "\22" then
    if vim.fn.getregion then
      local ok, lines = pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
      if ok and type(lines) == "table" and #lines > 0 then
        return table.concat(lines, "\n")
      end
    end
  end
  -- Last visual marks ('< / '>)
  local s = vim.fn.getpos("'<")
  local e = vim.fn.getpos("'>")
  if s[2] == 0 or e[2] == 0 then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(0, s[2] - 1, e[2], false)
  if #lines == 0 then
    return nil
  end
  -- Trim column range for character-wise last selection when possible
  if #lines == 1 then
    local c1 = math.max(1, s[3])
    local c2 = math.max(c1, e[3])
    lines[1] = lines[1]:sub(c1, c2)
  elseif #lines > 1 then
    local c1 = math.max(1, s[3])
    local c2 = math.max(1, e[3])
    lines[1] = lines[1]:sub(c1)
    lines[#lines] = lines[#lines]:sub(1, c2)
  end
  return table.concat(lines, "\n")
end

function M.gather()
  -- Prefer real editor file behind pi floats (ask/chat current buf is pi://*)
  local path
  local ok_ui, ui = pcall(require, "pi.ui")
  if ok_ui and ui.editor_path then
    path = ui.editor_path()
  end
  if not path then
    local name = vim.api.nvim_buf_get_name(0)
    if name ~= "" and not name:match("^pi://") then
      path = name
    end
  end
  local diags = {}
  -- diagnostics from editor buf when we can resolve it
  local diag_buf = 0
  if path then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(b) == path then
        diag_buf = b
        break
      end
    end
  end
  for _, d in ipairs(vim.diagnostic.get(diag_buf)) do
    table.insert(diags, string.format("L%d: %s", d.lnum + 1, d.message))
  end
  return {
    file = path,
    selection = selection_text(),
    diagnostics = diags,
  }
end

function M.expand(text)
  if type(text) ~= "string" then
    return text
  end
  local out = text
  if out:find("@this", 1, true) then
    local sel = selection_text()
    if not sel then
      local line = vim.api.nvim_get_current_line()
      sel = line
    end
    out = out:gsub("@this", sel or "")
  end
  if out:find("@buffer", 1, true) then
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    out = out:gsub("@buffer", table.concat(lines, "\n"))
  end
  if out:find("@visible", 1, true) then
    local chunks = {}
    local seen = {}
    local function add_buf(b)
      if seen[b] or not vim.api.nvim_buf_is_loaded(b) then
        return
      end
      local name = vim.api.nvim_buf_get_name(b)
      if name:match("^pi://") then
        return
      end
      seen[b] = true
      local label = name ~= "" and name or ("[buf " .. b .. "]")
      local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
      table.insert(chunks, "--- " .. label .. " ---\n" .. table.concat(lines, "\n"))
    end
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      add_buf(vim.api.nvim_win_get_buf(w))
    end
    -- always include current buffer even if not visible in a win (headless)
    add_buf(vim.api.nvim_get_current_buf())
    out = out:gsub("@visible", #chunks > 0 and table.concat(chunks, "\n\n") or "(no visible files)")
  end
  if out:find("@diagnostics", 1, true) then
    local g = M.gather()
    local block = #g.diagnostics > 0 and table.concat(g.diagnostics, "\n") or "(no diagnostics)"
    out = out:gsub("@diagnostics", block)
  end
  return out
end

function M.preamble()
  local g = M.gather()
  local parts = {}
  if g.file then
    table.insert(parts, "Current file: " .. g.file)
  end
  if g.selection then
    table.insert(parts, "Selection:\n" .. g.selection)
  end
  if g.diagnostics and #g.diagnostics > 0 then
    table.insert(parts, "Diagnostics:\n" .. table.concat(g.diagnostics, "\n"))
  end
  return table.concat(parts, "\n\n")
end

local function git_repo_root(anchor)
  -- finddir returns ".git" or ".../.git/"; :p adds a trailing slash, and
  -- vim.fs.dirname(".../.git/") wrongly yields ".../.git" — strip first.
  local git = vim.fn.finddir(".git", anchor .. ";")
  if git == "" then
    git = vim.fn.findfile(".git", anchor .. ";")
  end
  if git ~= "" then
    local abs_git = vim.fn.fnamemodify(git, ":p"):gsub("/+$", "")
    return vim.fn.fnamemodify(abs_git, ":h")
  end
  return nil
end

--- Prefer git root of the editor buffer behind pi floats; else cwd
function M.project_root()
  local anchor
  local ok_ui, ui = pcall(require, "pi.ui")
  if ok_ui and ui.editor_path then
    local ep = ui.editor_path()
    if ep then
      anchor = vim.fn.fnamemodify(ep, ":h")
    end
  end
  if not anchor then
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(w)
      if not cfg.relative or cfg.relative == "" then
        local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
        if name ~= "" and not name:match("^pi://") then
          anchor = vim.fn.fnamemodify(name, ":p:h")
          break
        end
      end
    end
  end
  if not anchor then
    local name = vim.api.nvim_buf_get_name(0)
    if name ~= "" and not name:match("^pi://") then
      anchor = vim.fn.fnamemodify(name, ":p:h")
    end
  end
  anchor = anchor or vim.fn.getcwd()
  return git_repo_root(anchor) or vim.fn.fnamemodify(anchor, ":p"):gsub("/+$", "")
end

local function editor_rel_file(root)
  root = root:gsub("/+$", "")
  local ok_ui, ui = pcall(require, "pi.ui")
  if ok_ui and ui.editor_path then
    local abs = ui.editor_path()
    if abs and vim.startswith(abs, root .. "/") then
      return abs:sub(#root + 2)
    end
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(w)
    if not cfg.relative or cfg.relative == "" then
      local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
      if name ~= "" and not name:match("^pi://") then
        local abs = vim.fn.fnamemodify(name, ":p")
        if vim.startswith(abs, root .. "/") then
          return abs:sub(#root + 2)
        end
        break
      end
    end
  end
  return nil
end

local function path_depth(p)
  local n = 0
  for _ in p:gmatch("/") do
    n = n + 1
  end
  return n
end

local function list_project_files(root)
  root = vim.fn.fnamemodify(root, ":p"):gsub("/+$", "")
  local files = {}
  local git_dir = root .. "/.git"
  if vim.fn.isdirectory(git_dir) == 1 or vim.fn.filereadable(git_dir) == 1 then
    files = vim.fn.systemlist({
      "git",
      "-C",
      root,
      "ls-files",
      "--cached",
      "--others",
      "--exclude-standard",
    })
  else
    for _, f in ipairs(vim.fn.glob(root .. "/**/*", false, true)) do
      if vim.fn.isdirectory(f) == 0 and vim.startswith(f, root .. "/") then
        table.insert(files, f:sub(#root + 2))
      end
    end
  end

  local cleaned = {}
  for _, f in ipairs(files) do
    if type(f) == "string" and f ~= "" and not f:match("^fatal:") then
      table.insert(cleaned, f)
    end
  end
  files = cleaned

  -- current file → shallow (project-folder) paths → alpha
  local current = editor_rel_file(root)
  table.sort(files, function(a, b)
    if current then
      if a == current then
        return true
      end
      if b == current then
        return false
      end
    end
    local da, db = path_depth(a), path_depth(b)
    if da ~= db then
      return da < db
    end
    return a < b
  end)
  return files
end

function M.pick_file(cb)
  local root = M.project_root()
  local files = list_project_files(root)
  if #files == 0 then
    vim.notify("pi: no files under " .. root, vim.log.levels.WARN)
    return
  end

  -- Keep ask open; drop zindex so telescope sits on top (via ui.with_picker).
  require("pi.ui").with_picker(function(done)
    vim.ui.select(files, {
      prompt = "pi @file · " .. vim.fn.fnamemodify(root, ":~"),
    }, function(item)
      done()
      if item and cb then
        cb(item)
      elseif require("pi.ui").is_input_open() then
        vim.cmd("startinsert!")
      end
    end)
  end)
end

return M
