-- Remember the last real editor per working directory, not a picker, sidebar or diff preview.
local M = {}
local saved = {}

local function path(cwd)
  return vim.fn.stdpath("state") .. "/last-file/" .. vim.fn.sha256(cwd) .. ".json"
end

local function remember()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local file = vim.api.nvim_buf_get_name(buf)
  if
    vim.bo[buf].buftype ~= ""
    or not vim.bo[buf].buflisted
    or vim.wo[win].diff
    or vim.api.nvim_win_get_config(win).relative ~= ""
    or vim.fn.filereadable(file) ~= 1
  then
    return
  end
  saved[vim.fn.getcwd()] = { file = file, view = vim.fn.winsaveview() }
end

local function restore()
  local argc = vim.fn.argc()
  local directory = argc == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1
  if argc ~= 0 and not directory or vim.g.SessionLoad then
    return
  end
  local cwd = vim.fn.getcwd()
  local ok, lines = pcall(vim.fn.readfile, path(cwd))
  if not ok then
    return
  end
  local decoded, state = pcall(vim.json.decode, table.concat(lines, "\n"))
  if
    not decoded
    or type(state) ~= "table"
    or type(state.file) ~= "string"
    or type(state.view) ~= "table"
    or vim.fn.filereadable(state.file) ~= 1
  then
    return
  end
  local initial = vim.api.nvim_get_current_buf()
  vim.schedule(function()
    -- Do not replace something opened by a startup command or by the user.
    if vim.api.nvim_get_current_buf() ~= initial or vim.bo[initial].modified then
      return
    end
    local name = vim.api.nvim_buf_get_name(initial)
    if
      vim.bo[initial].filetype ~= "snacks_dashboard"
      and (name ~= "" and vim.fn.isdirectory(name) ~= 1 or vim.bo[initial].buftype ~= "")
    then
      return
    end
    vim.cmd.edit(vim.fn.fnameescape(state.file))
    vim.fn.winrestview(state.view)
    if directory and vim.api.nvim_buf_is_valid(initial) then
      vim.api.nvim_buf_delete(initial, {})
    end
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("ResumeLastFile", { clear = true })
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, { group = group, callback = remember })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      remember()
      for cwd, state in pairs(saved) do
        local file = path(cwd)
        vim.fn.mkdir(vim.fs.dirname(file), "p")
        pcall(vim.fn.writefile, { vim.json.encode(state) }, file)
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimEnter", { group = group, once = true, callback = restore })
end

return M
