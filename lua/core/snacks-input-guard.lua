-- Snacks applies the text typed in a picker's input after a short debounce and then calls
-- `input.picker:find()`, but `Input:close()` sets `picker` to nil. Enter (or Esc) pressed within that
-- debounce closes the picker first and the late find fails with "attempt to index field 'picker'",
-- an error prompt that blocks the editor. Closing keeps a harmless stand-in (still holding no
-- reference to the picker, which is what the nil is for), so a late find does nothing.
local M = {}

function M.setup()
  local ok, input = pcall(require, "snacks.picker.core.input")
  if not ok or input._close_guarded then
    return
  end
  input._close_guarded = true
  local close = input.close
  input.close = function(self, ...)
    close(self, ...)
    self.picker = { find = function() end, closed = true }
  end
end

vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("SnacksInputGuard", { clear = true }),
  once = true,
  callback = M.setup,
})

return M
