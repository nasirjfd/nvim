-- The file name at the left of the command line (the line `:q` and `:w` are typed on), hidden
-- while a command is being typed. Neovim has no slot there, so it is a one-row floating window
-- laid over the start of that row; the blame and line:col stay in the ruler on the right.
-- Restore it as soon as the command line closes, including in diff views.
local M = {}

local buf, win, shown
local editor_windows = {}

local function ensure_buf()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "hide"
  end
  return buf
end

local function hide()
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_config, win, { hide = true })
  end
  shown = nil
end

local function render()
  if vim.fn.mode() == "c" or vim.fn.getcmdwintype() ~= "" then
    return hide()
  end
  local tab = vim.api.nvim_get_current_tabpage()
  local current = vim.api.nvim_get_current_win()
  local function is_file_window(candidate)
    if not candidate or not vim.api.nvim_win_is_valid(candidate) then
      return false
    end
    local b = vim.api.nvim_win_get_buf(candidate)
    return vim.api.nvim_win_get_config(candidate).relative == ""
      and vim.bo[b].buftype == ""
      and vim.api.nvim_buf_get_name(b) ~= ""
  end
  local target = current
  if is_file_window(current) then
    editor_windows[tab] = current
  elseif is_file_window(editor_windows[tab]) then
    target = editor_windows[tab]
  else
    for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if is_file_window(candidate) then
        target = candidate
        break
      end
    end
  end
  local ok, text = pcall(vim.api.nvim_win_call, target, _G.title_string)
  if not ok or not text or text == "" then
    return hide()
  end
  -- a file: its name first and clear, then the folder it is in, dim
  local name, dir = text, ""
  local target_buf = vim.api.nvim_win_get_buf(target)
  local path = vim.api.nvim_buf_get_name(target_buf)
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  local original, modified
  if lifecycle then
    original, modified = lifecycle.get_paths(tab)
  end
  local diff_path = modified and modified.absolute ~= "" and modified or original
  if diff_path and diff_path.absolute ~= "" then
    path = diff_path.absolute
  else
    diff_path = nil
  end
  if path ~= "" and (diff_path or vim.bo[target_buf].buftype == "") then
    name = vim.fn.fnamemodify(path, ":t") .. (vim.bo[target_buf].modified and " ●" or "")
    dir = vim.fn.fnamemodify(path, ":~:.:h")
    dir = (dir == "." or dir == "") and "" or ("  " .. dir)
    text = name .. dir
  end
  local width = vim.fn.strwidth(text) + 1
  local row = vim.o.lines - vim.o.cmdheight
  local key = text .. "|" .. width .. "|" .. row
  if shown == key and win and vim.api.nvim_win_is_valid(win) then
    return
  end
  local b = ensure_buf()
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { text })
  vim.api.nvim_buf_clear_namespace(b, -1, 0, -1)
  vim.api.nvim_buf_add_highlight(b, -1, "CmdlineFileName", 0, 0, #name)
  if dir ~= "" then
    vim.api.nvim_buf_add_highlight(b, -1, "CmdlineFilePath", 0, #name, -1)
  end
  local config = {
    relative = "editor",
    row = row,
    col = 0,
    width = math.min(width, math.floor(vim.o.columns / 2)),
    height = 1,
    style = "minimal",
    border = "none",
    focusable = false,
    zindex = 250,
    hide = false,
  }
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, config)
  else
    win = vim.api.nvim_open_win(b, false, config)
    vim.wo[win].winhighlight = "NormalFloat:Normal"
  end
  shown = key
end

local function set_highlights()
  local ok, normal = pcall(vim.api.nvim_get_hl, 0, { name = "Normal", link = false })
  if ok and normal.fg then
    vim.api.nvim_set_hl(0, "CmdlineFileName", { fg = normal.fg, bold = true })
  else
    vim.api.nvim_set_hl(0, "CmdlineFileName", { link = "Normal" })
  end
  vim.api.nvim_set_hl(0, "CmdlineFilePath", { link = "Comment" })
  shown = nil
end

function M.setup()
  local group = vim.api.nvim_create_augroup("CmdlineFile", { clear = true })
  set_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      set_highlights()
      vim.schedule(render)
    end,
  })
  -- Only events that can change the name or the row: nothing runs per cursor move or keystroke.
  vim.api.nvim_create_autocmd({
    "BufEnter",
    "WinEnter",
    "TabEnter",
    "BufModifiedSet",
    "BufFilePost",
    "DirChanged",
    "VimResized",
    "InsertLeave",
  }, { group = group, callback = vim.schedule_wrap(render) })
  -- The diff view switches files without a buffer event of its own
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "CodeDiffOpen", "CodeDiffClose", "CodeDiffFileSelect" },
    callback = vim.schedule_wrap(render),
  })
  -- Both executed and cancelled commands restore the filename without waiting for cursor movement.
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = group,
    callback = function()
      vim.schedule(function()
        shown = nil
        render()
      end)
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = group,
    callback = function()
      hide()
    end,
  })
  vim.schedule(render)
end

M.setup()

return M
