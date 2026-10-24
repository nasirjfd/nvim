-- ════════════════════════════════════════════════════════════════════════════
-- Essential Operations
-- ════════════════════════════════════════════════════════════════════════════

-- Save
vim.keymap.set("n", "<C-s>", "<cmd>w<cr>", { desc = "Save File" })
vim.keymap.set({ "i", "x" }, "<C-s>", "<Esc><cmd>w<cr>", { desc = "Save File" })

-- Quit
vim.keymap.set("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })
vim.keymap.set("n", "<leader>Q", "<cmd>qa<cr>", { desc = "Quit All" })

-- Close Neovim entirely, prompting to save any unsaved changes
vim.keymap.set("n", "<C-q>", "<cmd>confirm qa<cr>", { desc = "Close Neovim (confirm save)" })

-- Clear search highlight
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear Highlight", silent = true })

-- ════════════════════════════════════════════════════════════════════════════
-- Window Navigation (no prefix for speed)
-- ════════════════════════════════════════════════════════════════════════════

vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Go Left" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Go Down" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Go Up" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Go Right" })

-- Window resizing
vim.keymap.set("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase Height" })
vim.keymap.set("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease Height" })
vim.keymap.set("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease Width" })
vim.keymap.set("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase Width" })

-- ════════════════════════════════════════════════════════════════════════════
-- Line Movement (Visual Mode)
-- ════════════════════════════════════════════════════════════════════════════

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move Lines Down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move Lines Up" })

-- ════════════════════════════════════════════════════════════════════════════
-- Better Navigation
-- ════════════════════════════════════════════════════════════════════════════

-- Wrapped line navigation
vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, desc = "Up (wrapped)" })
vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, desc = "Down (wrapped)" })

-- Start/End of line (easier than ^ and $)
vim.keymap.set({ "n", "x", "o" }, "H", "^", { desc = "Start of Line" })
vim.keymap.set({ "n", "x", "o" }, "L", "g_", { desc = "End of Line" })

-- Keep search results centered
vim.keymap.set("n", "n", "nzzzv", { desc = "Next Match (centered)" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Prev Match (centered)" })
vim.keymap.set("n", "*", "*zzzv", { desc = "Search Word (centered)" })
vim.keymap.set("n", "#", "#zzzv", { desc = "Search Word Back (centered)" })

-- Buffer navigation
vim.keymap.set("n", "[b", "<cmd>bprevious<cr>", { desc = "Prev Buffer" })
vim.keymap.set("n", "]b", "<cmd>bnext<cr>", { desc = "Next Buffer" })

-- ════════════════════════════════════════════════════════════════════════════
-- Better Editing
-- ════════════════════════════════════════════════════════════════════════════

-- Better indenting (stay in visual mode)
vim.keymap.set("v", "<", "<gv", { desc = "Indent Left" })
vim.keymap.set("v", ">", ">gv", { desc = "Indent Right" })

-- Paste over selection without yanking
vim.keymap.set("v", "p", '"_dP', { desc = "Paste (no yank)" })

-- Yank block
vim.keymap.set("n", "YY", "va{Vy", { desc = "Yank Block {}" })

-- Split line (opposite of J)
vim.keymap.set(
  "n",
  "X",
  ":keeppatterns substitute/\\s*\\%#\\s*/\\r/e <bar> normal! ==^<cr>",
  { desc = "Split Line", silent = true }
)

-- Select all
vim.keymap.set("n", "<C-a>", "ggVG", { desc = "Select All" })

-- ════════════════════════════════════════════════════════════════════════════
-- Terminal Mode
-- ════════════════════════════════════════════════════════════════════════════

vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit Terminal Mode" })
vim.keymap.set("t", "<C-h>", "<cmd>wincmd h<cr>", { desc = "Go Left" })
vim.keymap.set("t", "<C-j>", "<cmd>wincmd j<cr>", { desc = "Go Down" })
vim.keymap.set("t", "<C-k>", "<cmd>wincmd k<cr>", { desc = "Go Up" })
vim.keymap.set("t", "<C-l>", "<cmd>wincmd l<cr>", { desc = "Go Right" })

local function copy_codex_reference(selection)
  local file = vim.fn.expand("%:p")
  if file == "" or vim.bo.buftype ~= "" then
    vim.notify("Current buffer has no file reference", vim.log.levels.WARN)
    return
  end

  local reference_path = vim.fn.fnamemodify(file, ":.")
  local reference
  if selection then
    local start_line = vim.fn.getpos("v")[2]
    local end_line = vim.fn.line(".")
    if start_line > end_line then
      start_line, end_line = end_line, start_line
    end
    reference = string.format("File: @%s\nLines: %d-%d", reference_path, start_line, end_line)
  else
    reference = string.format("File: @%s\nLine: %d", reference_path, vim.fn.line("."))
  end

  local copied = pcall(vim.fn.setreg, "+", reference)
  if vim.fn.has("mac") == 1 then
    vim.fn.system({ "pbcopy" }, reference)
    copied = vim.v.shell_error == 0
  end

  if copied then
    vim.notify("Copied Codex reference: " .. reference)
  else
    vim.notify("Could not copy Codex reference", vim.log.levels.ERROR)
  end
end

vim.keymap.set("n", "<leader>cx", function()
  copy_codex_reference(false)
end, { desc = "Copy Codex File Reference" })

vim.keymap.set("x", "<leader>cx", function()
  copy_codex_reference(true)
end, { desc = "Copy Codex Selection Reference" })

local ghostty_cmd_l = vim.api.nvim_replace_termcodes("<Esc>[99~", true, false, true)

vim.keymap.set("n", "<D-l>", function()
  copy_codex_reference(false)
end, { desc = "Copy Codex File Reference" })

vim.keymap.set("x", "<D-l>", function()
  copy_codex_reference(true)
end, { desc = "Copy Codex Selection Reference" })

vim.keymap.set("n", ghostty_cmd_l, function()
  copy_codex_reference(false)
end, { desc = "Copy Codex File Reference" })

vim.keymap.set("x", ghostty_cmd_l, function()
  copy_codex_reference(true)
end, { desc = "Copy Codex Selection Reference" })

vim.keymap.set({ "n", "v" }, "m", "%")
vim.keymap.set("n", "vp", "viwp")

vim.keymap.set("n", "<leader>op", function()
  vim.cmd("split")
  require("dbee").open({
    source = "Production",
  })
end)

vim.keymap.set("n", "<leader>ga", function()
  Snacks.terminal.open(
    "cd /Users/nasirjd/Can/Develop/Shell/git-changes-fzf-lazygit/ && ./git-all-select.sh",
    {
      interactive = true,
      win = {
        position = "float",
        border = "rounded",
      },
    }
  )
end, { desc = "Git all repos" })

vim.keymap.set("n", "gh", vim.diagnostic.open_float)

-- ════════════════════════════════════════════════════════════════════════════
-- Reload Config
-- ════════════════════════════════════════════════════════════════════════════

-- Re-sources options/keymaps in the running instance (no process restart, so
-- no risk of the terminal-corruption mess a real "quit and relaunch" caused).
-- Deliberately skips core.autocmds (autocmds defined without a group would
-- pile up duplicates on repeated reloads) and core.lazy (re-running the
-- plugin manager's setup() isn't meant to be called twice).
vim.keymap.set("n", "<leader>rr", function()
  for _, name in ipairs({ "core.options", "core.keymaps", "core.gui-keymaps" }) do
    package.loaded[name] = nil
    local ok, err = pcall(require, name)
    if not ok then
      vim.notify("Reload failed on " .. name .. ": " .. err, vim.log.levels.ERROR, { title = "Reload Config" })
      return
    end
  end
  vim.notify("Config reloaded", vim.log.levels.INFO, { title = "Reload Config" })
end, { desc = "Reload Config" })

vim.keymap.set("n", "<leader>gp", function()
  vim.ui.input({ prompt = "Commit message: " }, function(msg)
    if msg then
      vim.cmd("!git commit -m " .. vim.fn.shellescape(msg))
    end
  end)
end)
