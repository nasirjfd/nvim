-- ============================================================================
-- Cmd/Super-key bindings — mirrors the vscode-user-keybindings.json muscle
-- memory. These only fire under a client that forwards the Cmd modifier
-- (Neovide, or a terminal like Kitty/Ghostty/WezTerm configured to send it);
-- in a plain terminal they're inert, so this file is safe to keep either way.
-- ============================================================================
local map = vim.keymap.set

-- cmd+s -> save, staying in the current mode (insert/visual too)
-- Ghostty does not forward cmd+s by itself; its config sends this sequence (keybind = super+s=csi:92~)
for _, lhs in ipairs({ "<D-s>", vim.api.nvim_replace_termcodes("<Esc>[92~", true, false, true) }) do
  map({ "n", "i", "x" }, lhs, "<cmd>write<cr>", { desc = "Save File" })
end

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
  local tab = vim.api.nvim_get_current_tabpage()
  local sidebars = require("core.sidebars")
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  local panel = lifecycle and lifecycle.get_panel_view(tab)
  if panel then
    require("codediff.ui.explorer").toggle_visibility(panel)
    return
  end
  -- Opening a file over the diff panes ends the codediff session but leaves its side pane (changed
  -- files, history, Source Control) on screen. Keep toggling that pane, not the file explorer, until
  -- the explorer is opened on purpose (then <D-b> toggles the explorer).
  local orphan = not sidebars.prefers_explorer(tab) and sidebars.orphan_panel(tab)
  if orphan and pcall(require("codediff.ui.explorer").toggle_visibility, orphan) then
    return
  end
  Snacks.explorer()
end, { desc = "Toggle Sidebar" })

-- cmd+shift+e -> toggle the file explorer (workbench.view.explorer), always, also inside a codediff tab
-- (cmd+b is the one that toggles that tab's own sidebar). It focuses the explorer of this tab, opening
-- it when needed, and reveals the current file when the tab is an ordinary one.
local function focus_explorer()
  local current_tab = vim.api.nvim_get_current_tabpage()
  local explorer
  for _, picker in ipairs(Snacks.picker.get({ source = "explorer" })) do
    local win = picker.list and picker.list.win and picker.list.win.win
    if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_tabpage(win) == current_tab then
      explorer = picker
      break
    end
  end

  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  local in_codediff = lifecycle and lifecycle.get_session(current_tab) ~= nil
  local buf = vim.api.nvim_get_current_buf()
  local ordinary = vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= ""
  if explorer then
    -- Already focused: toggle it away instead of doing nothing.
    local cur = vim.api.nvim_get_current_win()
    local list_win = explorer.list and explorer.list.win and explorer.list.win.win
    local input_win = explorer.input and explorer.input.win and explorer.input.win.win
    if cur == list_win or cur == input_win then
      explorer:close()
    else
      explorer:focus("list")
    end
  elseif ordinary and not in_codediff then
    explorer = Snacks.explorer.reveal()
    if explorer then
      explorer:focus("list")
    end
  else
    Snacks.explorer.open()
  end
end

map("n", "<D-S-e>", focus_explorer, { desc = "Toggle Explorer" })
-- Ghostty does not forward cmd+shift+e by itself; its config sends this sequence (keybind = super+shift+e=csi:98~)
map("n", vim.api.nvim_replace_termcodes("<Esc>[98~", true, false, true), focus_explorer, { desc = "Toggle Explorer" })

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
-- Ghostty does not forward cmd+r by itself; its config sends this sequence (keybind = super+r=csi:97~)
map("n", vim.api.nvim_replace_termcodes("<Esc>[97~<Esc>[97~", true, false, true), vim.lsp.buf.rename, { desc = "Rename Symbol" })

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

-- cmd+/ -> comment line, then move down (like JetBrains)
-- Ghostty does not forward cmd+/ by itself; its config sends this sequence (keybind = super+/=csi:95~)
local function comment_line_down()
  require("Comment.api").toggle.linewise.current()
  vim.cmd("normal! j")
end
local function comment_selection()
  require("Comment.api").toggle.linewise(vim.fn.visualmode())
end
for _, lhs in ipairs({ "<D-/>", vim.api.nvim_replace_termcodes("<Esc>[95~", true, false, true) }) do
  map("n", lhs, comment_line_down, { desc = "Comment Line + Down" })
  map("x", lhs, comment_selection, { desc = "Comment Selection" })
end

-- shift+cmd+g -> git panel
-- Toggles: closes the Source Control tab when it is the current one, jumps to it when open elsewhere.
local function toggle_git()
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  if not lifecycle then
    vim.cmd("CodeDiff scm")
    return
  end
  local function is_scm(tab)
    local panel = lifecycle.get_panel(tab)
    return panel and panel.data and panel.data.kind == "scm"
  end
  local current = vim.api.nvim_get_current_tabpage()
  if is_scm(current) then
    lifecycle.close(current)
    return
  end
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if is_scm(tab) then
      vim.api.nvim_set_current_tabpage(tab)
      return
    end
  end
  vim.cmd("CodeDiff scm")
end
map("n", "<D-S-g>", toggle_git, { desc = "Toggle Git" })

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

-- cmd+z / cmd+shift+z -> undo / redo (Ghostty sends them as CSI 94~ / 93~, see ghostty/config).
-- In a working-tree diff tab they undo in the file being compared from any pane, side panel included.
local function undo_or_redo(redo)
  return function()
    local tab = vim.api.nvim_get_current_tabpage()
    local lifecycle = package.loaded["codediff.ui.lifecycle"]
    local session = lifecycle and lifecycle.get_session(tab)
    if session and session.git_root and session.modified_revision == nil and not session.merge then
      require("codediff.ui.view.actions.hunk").undo(tab, redo)
    else
      vim.cmd(redo and "normal! \x12" or "normal! u")
    end
  end
end
for _, lhs in ipairs({ "<D-z>", vim.api.nvim_replace_termcodes("<Esc>[94~", true, false, true) }) do
  map("n", lhs, undo_or_redo(false), { desc = "Undo" })
  map("i", lhs, "<C-o>u", { desc = "Undo" })
end
for _, lhs in ipairs({ "<D-S-z>", vim.api.nvim_replace_termcodes("<Esc>[93~", true, false, true) }) do
  map("n", lhs, undo_or_redo(true), { desc = "Redo" })
  map("i", lhs, "<C-o><C-r>", { desc = "Redo" })
end
