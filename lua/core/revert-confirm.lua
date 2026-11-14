-- A read-only confirmation, not a searchable picker or text input.
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("RevertHunkConfirmation")

function M.ask(callback)
  local owner = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true)
  local buttons = "              [ Yes ]       [ No ]"
  local lines = {
    "",
    "  Revert this staged hunk?",
    "  This also removes it from the Git index.",
    "",
    buttons,
    "",
  }
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "revert_confirm"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  local width = math.max(1, math.min(54, vim.o.columns - 4))
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = #lines,
    row = math.max(0, math.floor((vim.o.lines - #lines - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
    style = "minimal",
    border = "rounded",
    title = " Revert Hunk ",
    title_pos = "center",
    footer = " Enter / y: Yes    n / Esc: No ",
    footer_pos = "center",
  })
  vim.wo[win].wrap = false
  vim.wo[win].winhighlight = "NormalFloat:NormalFloat,FloatBorder:DiagnosticWarn"
  api.nvim_buf_set_extmark(buf, ns, 2, 0, { end_col = #lines[3], hl_group = "Comment" })
  api.nvim_buf_set_extmark(buf, ns, 4, 14, { end_col = 21, hl_group = "PmenuSel" })
  api.nvim_win_set_cursor(win, { 5, 14 })

  local done = false
  local function finish(yes, already_closed)
    if done then
      return
    end
    done = true
    if not already_closed and api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
    if yes and api.nvim_win_is_valid(owner) then
      api.nvim_set_current_win(owner)
    end
    vim.schedule(function()
      callback(yes)
    end)
  end
  local modes = { "n", "i", "x", "s" }
  for code = 32, 126 do
    local key = code == 60 and "<lt>" or vim.fn.nr2char(code)
    vim.keymap.set(modes, key, "<Nop>", { buffer = buf, nowait = true, silent = true })
  end
  for _, key in ipairs({ "<CR>", "y", "Y" }) do
    vim.keymap.set(modes, key, function()
      finish(true)
    end, { buffer = buf, nowait = true, silent = true })
  end
  for _, key in ipairs({ "n", "N", "<Esc>", "<C-c>" }) do
    vim.keymap.set(modes, key, function()
      finish(false)
    end, { buffer = buf, nowait = true, silent = true })
  end
  api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      finish(false, true)
    end,
  })
end

return M
