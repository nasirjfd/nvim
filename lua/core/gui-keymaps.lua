-- ============================================================================
-- Cmd/Super-key bindings — mirrors the vscode-user-keybindings.json muscle
-- memory. These only fire under a client that forwards the Cmd modifier
-- (Neovide, or a terminal like Kitty/Ghostty/WezTerm configured to send it);
-- in a plain terminal they're inert, so this file is safe to keep either way.
--
-- Ghostty: keys it doesn't forward on its own are bound in ghostty/config to send the kitty
-- keyboard encoding (e.g. super+s=csi:115;9u), which Neovim reads as the real <D-…>/<M-…> key.
-- Don't use made-up codes like csi:92~ — Neovim 0.12 silently drops unknown CSI ~ sequences.
-- ============================================================================
local map = vim.keymap.set

-- cmd+s -> save, staying in the current mode (insert/visual too)
map({ "n", "i", "x" }, "<D-s>", "<cmd>write<cr>", { desc = "Save File" })

-- cmd+c -> copy the selection to the system clipboard and keep it selected, like VS Code; with
-- nothing selected it copies the current line
map("x", "<D-c>", '"+ygv', { desc = "Copy Selection" })
map("n", "<D-c>", '"+yy', { desc = "Copy Line" })

-- cmd+e -> recent files
map("n", "<D-e>", function()
  Snacks.picker.recent()
end, { desc = "Recent Files" })

-- cmd+shift+o -> all files (recent files sorted to the top, see snacks.lua matcher opts)
map("n", "<D-S-o>", function()
  Snacks.picker.files()
end, { desc = "All Files" })
-- with a selection: the search box starts with the selected text (first line), editable
map("x", "<D-S-o>", function()
  local text = table.concat(
    vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() }),
    "\n"
  )
  vim.cmd("normal! \27")
  Snacks.picker.files({ pattern = text:match("^[^\n]*") })
end, { desc = "All Files (selection)" })

-- cmd+b -> toggle the sidebar (show/hide), matches workbench.action.toggleSidebarVisibility.
-- In a codediff tab (diff, history or the multi-repo Source Control pane) it
-- toggles that tab's own sidebar; anywhere else it toggles the file explorer.
map("n", "<D-b>", function()
  local tab = vim.api.nvim_get_current_tabpage()
  local sidebars = require("core.sidebars")
  -- the HTTP Requests or the Tests pane was the sidebar opened last: toggle that
  if sidebars.last(tab) == "http" then
    require("modules.http_requests").show_hide()
    return
  end
  if sidebars.last(tab) == "tests" then
    require("modules.phpunit.pane").show_hide()
    return
  end
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  local panel = lifecycle and lifecycle.get_panel_view(tab)
  -- The file explorer was the sidebar opened last (e.g. cmd+shift+e in the git tab): toggle that.
  if panel and sidebars.prefers_explorer(tab) then
    Snacks.explorer()
    return
  end
  if panel then
    if panel.is_hidden then
      sidebars.make_room_for_codediff(tab)
    end
    require("codediff.ui.explorer").toggle_visibility(panel)
    return
  end
  -- Opening a file over the diff panes ends the codediff session but leaves its side pane (changed
  -- files, history, Source Control) on screen. Keep toggling that pane, not the file explorer, until
  -- the explorer is opened on purpose (then <D-b> toggles the explorer).
  local orphan = not sidebars.prefers_explorer(tab) and sidebars.orphan_panel(tab)
  if orphan and orphan.is_hidden then
    sidebars.make_room_for_codediff(tab)
  end
  if orphan and pcall(require("codediff.ui.explorer").toggle_visibility, orphan) then
    return
  end
  Snacks.explorer()
end, { desc = "Toggle Sidebar" })

-- cmd+shift+e -> focus the file explorer (workbench.view.explorer), always, also inside a codediff tab
-- (cmd+b is the one that toggles that tab's own sidebar). It focuses the explorer of this tab, opening
-- it when needed, and reveals the current file when the tab is an ordinary one.
local function focus_explorer()
  local current_tab = vim.api.nvim_get_current_tabpage()
  local explorer
  for _, picker in ipairs(Snacks.picker.get({ source = "explorer" })) do
    local win = picker.list and picker.list.win and picker.list.win.win
    if
      win
      and vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_tabpage(win) == current_tab
    then
      explorer = picker
      break
    end
  end

  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  local in_codediff = lifecycle and lifecycle.get_session(current_tab) ~= nil
  local buf = vim.api.nvim_get_current_buf()
  local ordinary = vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= ""
  if explorer then
    -- Already open: only move the cursor into it, never close it.
    explorer:focus("list")
  elseif ordinary and not in_codediff then
    explorer = Snacks.explorer.reveal()
    if explorer then
      explorer:focus("list")
    end
  else
    Snacks.explorer.open()
  end
end

map("n", "<D-S-e>", focus_explorer, { desc = "Focus Explorer" })

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

-- cmd+r cmd+r -> rename symbol: the first cmd+r opens the replace bar, the second one in the bar
-- renames (core/find-bar.lua), so a single cmd+r doesn't wait for a second key

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
local function comment_line_down()
  require("Comment.api").toggle.linewise.current()
  vim.cmd("normal! j")
end
local function comment_selection()
  -- The '< and '> marks are only set once Visual mode is left, so leave it first; otherwise the
  -- previous selection's lines were commented (or "E16: Invalid range")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  require("Comment.api").toggle.linewise(vim.fn.visualmode())
end
map("n", "<D-/>", comment_line_down, { desc = "Comment Line + Down" })
map("x", "<D-/>", comment_selection, { desc = "Comment Selection" })

-- shift+cmd+g -> git panel
-- Focuses the Source Control pane, never toggles it: jumps to its tab and puts the cursor in it,
-- opening it when there is none. The tab is never closed by this key, so the repository list keeps
-- its rows and positions and its file watcher keeps it current (the tab line is off, so a tab out of
-- view is invisible). `q` in the pane closes it for good.
local function focus_git()
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  if not lifecycle then
    vim.cmd("CodeDiff scm")
    return
  end
  -- the file being edited (also when the cursor is in the file explorer)
  local scm_handler = package.loaded["codediff.commands.handlers.scm"]
  local from = scm_handler and scm_handler.editor_buffer and scm_handler.editor_buffer() or vim.api.nvim_get_current_buf()
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local panel = lifecycle.get_panel(tab)
    if panel and panel.data and panel.data.kind == "scm" then
      local came_from_other_tab = tab ~= vim.api.nvim_get_current_tabpage()
      vim.api.nvim_set_current_tabpage(tab)
      -- with no change selected, the right side shows the file you came from (like VS Code)
      if came_from_other_tab then
        local view_module = package.loaded["codediff.ui.view"]
        if view_module and view_module.set_home_buffer then
          pcall(view_module.set_home_buffer, tab, from)
        end
      end
      -- cmd+shift+e in the git tab swaps its sidebar for the file explorer: bring the git one back,
      -- since that is what this key is for.
      local view = lifecycle.get_panel_view(tab)
      if view and view.is_hidden then
        -- the other sidebars go first, in the same tick, so they are never on screen together
        require("core.sidebars").make_room_for_codediff(tab)
        require("codediff.ui.explorer").toggle_visibility(view)
      end
      if view and view.winid and vim.api.nvim_win_is_valid(view.winid) then
        vim.api.nvim_set_current_win(view.winid)
      end
      return
    end
  end
  vim.cmd("CodeDiff scm")
end
map("n", "<D-S-g>", focus_git, { desc = "Focus Git" })

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

-- shift+option+f -> format the selection (visual mode) or the whole file (normal mode), like VS Code.
-- Ghostty types a character for option+shift+f, so its config sends the key as alt+shift+f
-- instead (keybind = alt+shift+f=csi:102;4u), which Neovim reads as <M-F>.
local function format_buffer_or_selection()
  local range
  local mode = vim.api.nvim_get_mode().mode
  if mode == "v" or mode == "V" or mode == "\22" then
    -- Whole selected lines, ending past the last character: conform's own visual range stops one
    -- character short, so stylua/prettier skip the last statement as only partly selected.
    local first, last = vim.fn.line("v"), vim.fn.line(".")
    if first > last then
      first, last = last, first
    end
    range = { start = { first, 0 }, ["end"] = { last, #vim.fn.getline(last) } }
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  end
  require("conform").format({ async = true, range = range }, function(err)
    if err then
      vim.notify(err, vim.log.levels.WARN, { title = "Format" })
    end
  end)
end
map({ "n", "x" }, "<M-F>", format_buffer_or_selection, { desc = "Format Selection / File" })

-- alt+cmd+z -> revert the hunk under the cursor. In a diff tab that is codediff's discard-hunk (working
-- tree side, no confirmation: cmd+z / u bring it back); elsewhere gitsigns' reset hunk.
map("n", "<D-M-z>", function()
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  if lifecycle and lifecycle.get_session(vim.api.nvim_get_current_tabpage()) then
    local config = require("codediff.config")
    local key = config.options.keymaps.view.discard_hunk
    if key then
      local before = config.options.diff.confirm_discard_hunk
      config.options.diff.confirm_discard_hunk = false
      pcall(vim.api.nvim_feedkeys, vim.keycode(key), "mx", false)
      config.options.diff.confirm_discard_hunk = before
      return
    end
  end
  require("gitsigns").reset_hunk()
end, { desc = "Revert Hunk" })

-- cmd+z / cmd+shift+z -> undo / redo
-- In a working-tree diff tab they undo in the file being compared from any pane, side panel included.
local function undo_or_redo(redo)
  return function()
    local tab = vim.api.nvim_get_current_tabpage()
    local lifecycle = package.loaded["codediff.ui.lifecycle"]
    local session = lifecycle and lifecycle.get_session(tab)
    if session and session.git_root and session.modified_revision == nil and not session.merge then
      require("codediff.ui.view.actions.hunk").undo(tab, redo)
    elseif
      session
      and session.merge
      and session.result_win
      and vim.api.nvim_win_is_valid(session.result_win)
    then
      -- the merge view: one step back (or forward), buttons included, from any column
      local history = require("codediff.ui.conflict.history")
      if redo then
        history.redo(tab)
      else
        history.undo(tab)
      end
    elseif vim.bo.modifiable then
      vim.cmd(redo and "normal! \x12" or "normal! u")
    end
  end
end
map("n", "<D-z>", undo_or_redo(false), { desc = "Undo" })
map("i", "<D-z>", "<C-o>u", { desc = "Undo" })
map("n", "<D-S-z>", undo_or_redo(true), { desc = "Redo" })
map("i", "<D-S-z>", "<C-o><C-r>", { desc = "Redo" })

-- ════════════════════════════════════════════════════════════════════════════
-- Keep these last. <Esc><BS> below starts with <Esc>, so a lone <Esc> would wait for a possible
-- <BS>. A nowait <Esc> acts at once, but Neovim only honors nowait when it is defined after the
-- longer <Esc>… mappings; <Esc><BS> sent in one burst by the terminal still matches first.
-- ════════════════════════════════════════════════════════════════════════════

-- Option+Backspace deletes the previous word in insert mode, like macOS text fields. The terminal
-- delivers it as <M-BS>, or as <Esc><BS> when the two bytes are split.
map("i", "<M-BS>", "<C-w>", { desc = "Delete Previous Word" })
map("i", "<Esc><BS>", "<C-w>", { desc = "Delete Previous Word" })
map("c", "<M-BS>", "<C-w>", { desc = "Delete Previous Word" })
map("c", "<Esc><BS>", "<C-w>", { desc = "Delete Previous Word" })

-- <Esc> just leaves insert mode, with the cursor left where it is (the one for visual mode is in
-- keymaps.lua: after resizing a selection with Option+j/k it also restores the cursor)
map("i", "<Esc>", "<Esc>", { desc = "Leave Insert Mode", nowait = true })
