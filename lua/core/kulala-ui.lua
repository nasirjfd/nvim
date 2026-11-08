-- Hiding Kulala's response window safely.
--
-- Kulala hides it by deleting its buffer, which closes the window as a side effect. After an LSP
-- hover (gh) Neovim watches every closing window and reads that window's variables; a window closed
-- through a buffer delete is already gone by then, and Neovim raises "Invalid window id". Closing
-- the window first, while it is still valid, and deleting the buffer after avoids that.
local M = {}

function M.hide_response()
  local ok, ui = pcall(require, "kulala.ui")
  if not ok then
    return false
  end
  local buf = ui.get_kulala_buffer()
  if not buf then
    return false
  end
  local shown = false
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    shown = true
    if #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win)) > 1 then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  pcall(ui.close_kulala_buffer)
  return shown
end

return M
