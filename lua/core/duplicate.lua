local M = {}

function M.line()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(0, cursor[1] - 1, cursor[1], false)
  vim.api.nvim_buf_set_lines(0, cursor[1], cursor[1], false, line)
  vim.api.nvim_win_set_cursor(0, { cursor[1] + 1, cursor[2] })
end

function M.selection()
  -- Native yank/put handles Unicode, multiline, linewise and rectangular selections.
  -- Save every register it touches: duplication must not replace the user's clipboard.
  local saved = {}
  for _, reg in ipairs({ "z", "0", '"' }) do
    saved[reg] = vim.fn.getreginfo(reg)
  end
  local ok, err = pcall(function()
    vim.cmd('normal! "zy')
    local kind = vim.fn.getregtype("z"):sub(1, 1)
    if kind == "\22" then
      local first, last = vim.fn.getpos("'["), vim.fn.getpos("']")
      vim.fn.setpos(".", { 0, first[2], last[3], last[4] })
      vim.cmd('normal! "zp')
    else
      vim.cmd('normal! `]"zp')
    end
    -- Select the new copy, so another Cmd+D duplicates it again.
    local mode = kind == "V" and "V" or (kind == "\22" and "\22" or "v")
    vim.cmd("normal! `[" .. mode .. "`]")
  end)
  for _, reg in ipairs({ "z", "0", '"' }) do
    vim.fn.setreg(reg, saved[reg])
  end
  if not ok then
    error(err)
  end
end

return M
