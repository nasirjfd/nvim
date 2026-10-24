-- ============================================================================
-- Cmd/Super-key bindings — mirrors the vscode-user-keybindings.json muscle
-- memory. These only fire under a client that forwards the Cmd modifier
-- (Neovide, or a terminal like Kitty/Ghostty/WezTerm configured to send it);
-- in a plain terminal they're inert, so this file is safe to keep either way.
-- ============================================================================
local map = vim.keymap.set

-- cmd+e -> recent files
map("n", "<D-e>", function()
  Snacks.picker.recent()
end, { desc = "Recent Files" })

-- cmd+shift+o -> all files (recent files sorted to the top, see snacks.lua matcher opts)
map("n", "<D-S-o>", function()
  Snacks.picker.files()
end, { desc = "All Files" })

-- cmd+b -> toggle the sidebar (show/hide), matches workbench.action.toggleSidebarVisibility.
-- In a codediff tab (diff, history or the multi-repo Source Control pane) it
-- toggles that tab's own sidebar; anywhere else it toggles the file explorer.
map("n", "<D-b>", function()
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  local panel = lifecycle and lifecycle.get_panel_view(vim.api.nvim_get_current_tabpage())
  if panel then
    require("codediff.ui.explorer").toggle_visibility(panel)
  else
    Snacks.explorer()
  end
end, { desc = "Toggle Sidebar" })

-- cmd+f4 -> close buffer
map("n", "<D-F4>", function()
  Snacks.bufdelete()
end, { desc = "Close Buffer" })

-- cmd+d -> duplicate line/selection
map("n", "<D-d>", ":t.<cr>", { desc = "Duplicate Line" })
map("x", "<D-d>", ":t'>gv<cr>", { desc = "Duplicate Selection" })

-- cmd+' / shift+cmd+' -> toggle terminal / new terminal
map({ "n", "t" }, "<D-'>", function()
  Snacks.terminal()
end, { desc = "Toggle Terminal" })
map({ "n", "t" }, "<D-S-'>", function()
  Snacks.terminal()
end, { desc = "New Terminal" })

-- cmd+f12 -> goto symbol
map("n", "<D-F12>", function()
  Snacks.picker.lsp_symbols()
end, { desc = "Goto Symbol" })

-- cmd+r cmd+r -> rename symbol
map("n", "<D-r><D-r>", vim.lsp.buf.rename, { desc = "Rename Symbol" })

-- cmd+g -> goto line
map("n", "<D-g>", function()
  vim.ui.input({ prompt = "Go to line: " }, function(input)
    local line = tonumber(input)
    if line then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
    end
  end)
end, { desc = "Go to Line" })

-- cmd+h -> find & replace in buffer
map("n", "<D-h>", function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(":%s/", true, false, true), "n", false)
end, { desc = "Find & Replace" })

-- cmd+/ -> comment line, then move down (multi-command binding in vscode)
map("n", "<D-/>", function()
  require("Comment.api").toggle.linewise.current()
  vim.cmd("normal! j")
end, { desc = "Comment Line + Down" })
map("x", "<D-/>", function()
  require("Comment.api").toggle.linewise(vim.fn.visualmode())
end, { desc = "Comment Selection" })

-- shift+cmd+g -> git panel
map("n", "<D-S-g>", "<cmd>Neogit<cr>", { desc = "Git" })

-- cmd+shift+s -> DB client focus
map("n", "<D-S-s>", function()
  vim.cmd("split")
  require("dbee").open({ source = "Production" })
end, { desc = "Open DB Client" })

-- cmd+ctrl+j / cmd+ctrl+k -> insert cursor below/above (multicursor.nvim)
map({ "n", "x" }, "<D-C-j>", function()
  require("multicursor-nvim").lineAddCursor(1)
end, { desc = "Add Cursor Below" })
map({ "n", "x" }, "<D-C-k>", function()
  require("multicursor-nvim").lineAddCursor(-1)
end, { desc = "Add Cursor Above" })

-- alt+cmd+l -> format selection
map("x", "<D-M-l>", function()
  require("conform").format({ async = true })
end, { desc = "Format Selection" })

-- alt+cmd+z -> revert/reset hunk
map("n", "<D-M-z>", function()
  require("gitsigns").reset_hunk()
end, { desc = "Revert Hunk" })
