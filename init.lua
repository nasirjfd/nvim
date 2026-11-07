-- Started in a directory that no longer exists (the shell's folder was deleted or recreated under it):
-- getcwd() is empty and everything that runs a command there fails. Move to the home folder first.
if vim.fn.getcwd() == "" then
  pcall(vim.cmd.cd, vim.uv.os_homedir())
  -- `nvim .` left a buffer named "." that points nowhere: reading its undo file is the E823 error
  pcall(vim.cmd, "silent! argdelete *")
  pcall(vim.cmd, "silent! %bwipeout!")
end
vim.o.exrc = true
require("core")
