-- ============================================================================
-- Leader Keys
-- ============================================================================
vim.g.mapleader = " "      -- Set space as the leader key for custom mappings
vim.g.maplocalleader = " " -- Set space as the local leader key for buffer-local mappings

-- ============================================================================
-- Disable Built-in Plugins
-- ============================================================================
vim.g.loaded_netrw = 1       -- Disable netrw file explorer (using a different file explorer)
vim.g.loaded_netrwPlugin = 1 -- Disable netrw plugin component

-- ============================================================================
-- Disable Providers (silence health check warnings)
-- ============================================================================
vim.g.loaded_node_provider = 0    -- Disable Node.js provider
vim.g.loaded_perl_provider = 0    -- Disable Perl provider
vim.g.loaded_python3_provider = 0 -- Disable Python 3 provider
vim.g.loaded_ruby_provider = 0    -- Disable Ruby provider

-- ============================================================================
-- Editor Behavior
-- ============================================================================
vim.opt.mouse = "a"                                 -- Enable mouse support in all modes
vim.opt.clipboard = "unnamedplus"                   -- Use system clipboard for all yank/paste operations
vim.opt.undofile = true                             -- Persist undo history to disk between sessions
vim.opt.undodir = vim.fn.stdpath("data") .. "/undo" -- Directory to store undo files
vim.opt.updatetime = 100                            -- Time in ms before CursorHold event triggers (affects plugins)
vim.opt.timeoutlen = 1000                           -- Time in ms to wait for a mapped key sequence to complete
vim.opt.confirm = true                              -- Prompt for confirmation instead of failing on unsaved changes
vim.opt.autoread = true                             -- Automatically reload files changed outside of Neovim

-- ============================================================================
-- UI/Display
-- ============================================================================
vim.opt.termguicolors = true      -- Enable 24-bit RGB colors in the terminal
vim.opt.number = true             -- Show absolute line numbers
vim.opt.relativenumber = true     -- Show relative line numbers (hybrid with number=true)
vim.opt.numberwidth = 4           -- Minimum width of number column
vim.opt.signcolumn = "yes:1"      -- Always show sign column with width of 1
vim.opt.cursorline = false        -- Don't highlight the current line
vim.opt.wrap = false              -- Don't wrap long lines
vim.opt.breakindent = true        -- Wrapped lines preserve indentation
vim.opt.showmode = false          -- Don't show mode in command line (shown in statusline)
vim.opt.showcmd = false           -- Don't show partial command in command line
vim.opt.ruler = true              -- Show cursor position in command line
vim.opt.showtabline = 0           -- Never show the tab line
vim.opt.cmdheight = 1             -- Height of command line area
vim.opt.pumheight = 10            -- Maximum height of popup menu
vim.opt.fillchars = { eob = " " } -- Hide ~ characters on empty lines
vim.o.winborder = "rounded"       -- Use rounded borders for floating windows
-- vim.opt.pumborder = "rounded" -- Rounded border for completion popup menu (0.12+)

-- ============================================================================
-- Search
-- ============================================================================
vim.opt.hlsearch = true   -- Highlight all search matches
vim.opt.incsearch = true  -- Show search matches as you type
vim.opt.ignorecase = true -- Ignore case in search patterns
vim.opt.smartcase = true  -- Override ignorecase if pattern contains uppercase

-- ============================================================================
-- Indentation
-- ============================================================================
vim.opt.expandtab = true   -- Convert tabs to spaces
vim.opt.shiftwidth = 2     -- Number of spaces for each indentation level
vim.opt.smartindent = true -- Auto-indent new lines based on syntax

-- ============================================================================
-- Splits
-- ============================================================================
vim.opt.splitbelow = true -- Open horizontal splits below current window
vim.opt.splitright = true -- Open vertical splits to the right of current window

-- ============================================================================
-- Files
-- ============================================================================
if vim.bo.modifiable then
  vim.opt.fileencoding = "utf-8" -- File encoding for new files (skip on non-modifiable buffers, e.g. on config reload)
end
vim.opt.backup = false         -- Don't create backup files before overwriting
vim.opt.writebackup = false    -- Don't create backup while editing
vim.opt.swapfile = false       -- Don't create swap files

-- ============================================================================
-- Completion
-- ============================================================================
vim.opt.completeopt = { "menu", "menuone", "noselect" } -- Completion menu options
vim.opt.conceallevel = 0                                -- Show all text normally (no concealment)

-- ============================================================================
-- Other
-- ============================================================================
vim.opt.title = true              -- Set window title to filename
vim.opt.guifont = "monospace:h14" -- Font for GUI Neovim (e.g., Neovide)

-- ============================================================================
-- Filetype Detection
-- ============================================================================
vim.filetype.add({
    extension = {
        gotmpl = "gotmpl",  -- Go templates (registered for gopls)
        tmpl = "gotmpl",
    },
    filename = {
        [".envrc"] = "sh",  -- direnv files use bash syntax
    },
    pattern = {
        ["[jt]sconfig.*.json"] = "jsonc", -- Treat tsconfig/jsconfig files as JSONC (allows comments)
    },
})
-- GUI-launched Neovim may not inherit Homebrew's PATH, which prevents
-- external tools such as ripgrep from being found by plugins.
if vim.fn.has("mac") == 1 then
  local homebrew_bin = "/opt/homebrew/bin"
  local path = vim.env.PATH or ""
  if vim.fn.isdirectory(homebrew_bin) == 1 and not path:find(homebrew_bin, 1, true) then
    vim.env.PATH = homebrew_bin .. ":" .. path
  end
end

-- Current-line git blame (fed by gitsigns' current_line_blame). Neovim gives the ruler at most
-- about half the screen width, so it shortens to fit: the summary first, then the date goes.
function _G.blame_status()
  local d = vim.b.gitsigns_blame_line_dict
  if not d or not d.author then
    return ""
  end
  local position = ("  %d:%d"):format(vim.fn.line("."), vim.fn.col("."))
  local room = math.min(90, math.floor(vim.o.columns / 2)) - #position - 1
  local author = vim.fn.strcharpart(d.author, 0, math.max(room, 1))
  local date = os.date("%Y-%m-%d", tonumber(d.author_time))
  local summary_room = math.min(40, room - vim.fn.strwidth(author .. " • " .. date .. " • "))
  if summary_room >= 10 then
    local summary = vim.fn.strcharpart(d.summary or "", 0, summary_room)
    return ("%s • %s • %s"):format(author, date, summary)
  elseif room >= vim.fn.strwidth(author .. " • " .. date) then
    return author .. " • " .. date
  end
  return author
end

-- No status line under the window: the blame and line:col go to the right of the command line
-- (the ruler), and the file name goes to the terminal title. A status line still appears
-- between stacked splits, showing the file name there.
vim.opt.laststatus = 0
vim.opt.statusline = "%f %m%r%=%{v:lua.blame_status()}  %l:%c "
vim.opt.rulerformat = "%90(%=%{v:lua.blame_status()}  %l:%c%)"

-- Terminal title: the file path from the project root (Neovim's cwd), or the project name for
-- special buffers (explorer, pickers, terminals)
function _G.title_string()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" or vim.bo.buftype ~= "" then
    return vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
  end
  return vim.fn.fnamemodify(name, ":~:.") .. (vim.bo.modified and " ●" or "")
end
vim.opt.titlestring = "%{v:lua.title_string()}"
