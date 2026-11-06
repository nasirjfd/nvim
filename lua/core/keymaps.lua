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

-- The nowait <Esc> mappings for visual and insert mode (and Option+Backspace) are at the end of
-- core/gui-keymaps.lua: they must be defined after every <Esc>-prefixed mapping (<Esc><BS>).

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

local function copy_reference(selection)
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
    reference = string.format("@%s\nLines: %d-%d", reference_path, start_line, end_line)
  else
    reference = string.format("@%s\nLine: %d", reference_path, vim.fn.line("."))
  end

  local copied = pcall(vim.fn.setreg, "+", reference)
  if vim.fn.has("mac") == 1 then
    vim.fn.system({ "pbcopy" }, reference)
    copied = vim.v.shell_error == 0
  end

  if copied then
    vim.notify("Reference copied: " .. reference)
  else
    vim.notify("Could not copy reference", vim.log.levels.ERROR)
  end
end

vim.keymap.set("n", "<leader>cx", function()
  copy_reference(false)
end, { desc = "Copy File Reference" })

vim.keymap.set("x", "<leader>cx", function()
  copy_reference(true)
end, { desc = "Copy Selection Reference" })

-- cmd+l and cmd+shift+c copy the reference. Ghostty sends them in the kitty keyboard format
-- (ghostty/config: super+l=csi:108;9u, super+shift+c=csi:99;10u), which Neovim reads as <D-…>.
-- Inside herdr, cmd+l instead sends the @file#L reference to the pane labelled "claude"
-- (lua/core/herdr-ref.lua); cmd+shift+c keeps copying to the clipboard.
vim.keymap.set("n", "<D-l>", function()
  if vim.env.HERDR_PANE_ID then
    require("core.herdr-ref").send(false)
  else
    copy_reference(false)
  end
end, { desc = "Send/Copy File Reference" })
vim.keymap.set("x", "<D-l>", function()
  if vim.env.HERDR_PANE_ID then
    require("core.herdr-ref").send(true)
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
  else
    copy_reference(true)
  end
end, { desc = "Send/Copy Selection Reference" })

for _, lhs in ipairs({ "<D-S-c>" }) do
  vim.keymap.set("n", lhs, function()
    copy_reference(false)
  end, { desc = "Copy File Reference" })

  vim.keymap.set("x", lhs, function()
    copy_reference(true)
  end, { desc = "Copy Selection Reference" })
end

-- Option+k / Option+j expand / shrink the selection by syntax node, like VS Code's
-- Shift+Alt+Right/Left. This is what Neovim's default visual `an` / `in` do (treesitter node,
-- else LSP selection range), remembering the path so shrinking returns to the node you expanded
-- from. mini.ai takes over `an` / `in` ("around/inside next"), so call the same functions directly.
-- Ghostty sends these keys as alt+j/k (ghostty/config: alt+j=csi:106;3u, alt+k=csi:107;3u);
-- Option alone would type ∆ / ˚.
local function select_node(parent)
  if vim.treesitter.get_parser(nil, nil, { error = false }) then
    local select = require("vim.treesitter._select")
    if parent then
      select.select_parent(vim.v.count1)
    else
      select.select_child(vim.v.count1)
    end
  else
    vim.lsp.buf.selection_range(parent and vim.v.count1 or -vim.v.count1)
  end
end

-- Like JetBrains, the cursor stays where it was while the selection grows and shrinks around it:
-- Visual mode has to keep the cursor on one end of the selection, so it is the end nearest to where
-- it started, the window does not scroll while that end is on screen, and leaving with <Esc> puts the
-- cursor back exactly where it was before the first expansion.
local origin ---@type {buf: number, pos: number[]}?
-- Selections left behind by expanding, so shrinking walks back through exactly the same ones
local history = {} ---@type {first: number[], last: number[]}[]
local expected ---@type {first: number[], last: number[]}? the selection the last resize produced

local function before(a, b) -- position a is before position b ({line, col})
  return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
end

local function selection()
  local anchor, cursor = vim.fn.getpos("v"), vim.fn.getpos(".")
  local from, to = { anchor[2], anchor[3] - 1 }, { cursor[2], cursor[3] - 1 }
  if before(to, from) then
    from, to = to, from
  end
  return { first = from, last = to }
end

local function same(a, b)
  return a and b and a.first[1] == b.first[1] and a.first[2] == b.first[2] and a.last[1] == b.last[1] and a.last[2] == b.last[2]
end

--- Select first..last with the cursor on the end nearest to where the resizing started.
local function select_range(range)
  local first, last = range.first, range.last
  local function gap(p)
    return math.abs(p[1] - origin.pos[1]) * 1000 + math.abs(p[2] - origin.pos[2])
  end
  local at_first = gap(first) < gap(last)
  local from, to = unpack(at_first and { last, first } or { first, last })
  if vim.fn.mode():match("^[vV\22]") then
    vim.cmd("normal! \27")
  end
  vim.api.nvim_win_set_cursor(0, from)
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, to)
  expected = range
end

local function resize_selection(parent)
  local buf = vim.api.nvim_get_current_buf()
  if not origin or origin.buf ~= buf then
    origin = { buf = buf, pos = vim.api.nvim_win_get_cursor(0) }
    history, expected = {}, nil
  end
  local view = vim.fn.winsaveview()
  local current = selection()
  if parent then
    select_node(true)
    local grown = selection()
    if not same(grown, current) then
      table.insert(history, current)
    end
    select_range(grown)
  elseif #history > 0 and same(current, expected) then
    select_range(table.remove(history)) -- back to what it was before the last expansion
  else
    select_node(false)
    select_range(selection())
  end
  local line = vim.fn.line(".")
  if line >= view.topline and line <= view.topline + vim.api.nvim_win_get_height(0) - 1 then
    vim.fn.winrestview({ topline = view.topline, leftcol = view.leftcol })
  end
end

vim.keymap.set("n", "<M-k>", "v<M-k>", { remap = true, desc = "Expand Selection" })
vim.keymap.set("x", "<M-k>", function()
  resize_selection(true)
end, { desc = "Expand Selection" })
vim.keymap.set("x", "<M-j>", function()
  resize_selection(false)
end, { desc = "Shrink Selection" })
vim.keymap.set("x", "<Esc>", function()
  local saved = origin
  origin, history, expected = nil, {}, nil
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  if saved and saved.buf == vim.api.nvim_get_current_buf() then
    pcall(vim.api.nvim_win_set_cursor, 0, saved.pos)
  end
end, { desc = "End Selection", nowait = true })
-- Any other way out of Visual mode (an operator, a new selection) forgets the origin
vim.api.nvim_create_autocmd("ModeChanged", {
  pattern = "[vV\22]*:[^vV\22]*",
  callback = function()
    vim.schedule(function()
      if not vim.fn.mode():match("^[vV\22]") then
        origin, history, expected = nil, {}, nil
      end
    end)
  end,
})

-- The mouse wheel scrolls around a Visual selection without touching it, like JetBrains. In Vim the
-- cursor has to stay on screen, so scrolling past the selection's end drags the end along and the
-- selection grows with every tick. So the first wheel tick leaves Visual mode and draws the selection
-- as a highlight instead; the cursor is then free to follow the scroll. The next key that is not the
-- wheel puts the real selection back first (so `y`, `d`, <Esc>, <M-k>… act on it), a click just ends it.
local frozen ---@type {buf: number, mode: string, anchor: number[], cursor: number[], mark: number}?
local freeze_ns = vim.api.nvim_create_namespace("visual_scroll_freeze")

local function thaw(restore)
  local state = frozen
  if not state then
    return
  end
  frozen = nil
  pcall(vim.api.nvim_buf_clear_namespace, state.buf, freeze_ns, 0, -1)
  if restore and vim.api.nvim_get_current_buf() == state.buf then
    pcall(function()
      vim.api.nvim_win_set_cursor(0, state.anchor)
      vim.cmd("normal! " .. state.mode)
      vim.api.nvim_win_set_cursor(0, state.cursor)
    end)
  end
end

local function wheel_in_visual(key)
  return function()
    local mode = vim.fn.mode()
    if mode == "v" or mode == "V" then
      local buf = vim.api.nvim_get_current_buf()
      local a, c = vim.fn.getpos("v"), vim.fn.getpos(".")
      local anchor, cursor = { a[2], a[3] - 1 }, { c[2], c[3] - 1 }
      local first, last = anchor, cursor
      if before(cursor, anchor) then
        first, last = cursor, anchor
      end
      vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
      for line = first[1], last[1] do
        local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
        local from = (mode == "v" and line == first[1]) and first[2] or 0
        local to = (mode == "v" and line == last[1]) and math.min(last[2] + 1, #text) or #text
        vim.api.nvim_buf_set_extmark(buf, freeze_ns, line - 1, from, {
          end_row = line - 1,
          end_col = math.max(to, from),
          hl_group = "Visual",
          hl_eol = not (mode == "v" and line == last[1]),
          priority = 200,
        })
      end
      frozen = { buf = buf, mode = mode, anchor = anchor, cursor = cursor }
    end
    vim.api.nvim_feedkeys(vim.keycode(key), "n", false)
  end
end

for _, key in ipairs({ "<ScrollWheelDown>", "<ScrollWheelUp>" }) do
  vim.keymap.set("x", key, wheel_in_visual(key), { desc = "Scroll without changing the selection" })
end

vim.on_key(function(_, typed)
  if not frozen or not typed or typed == "" then
    return
  end
  local name = vim.fn.keytrans(typed)
  if name:find("^<ScrollWheel") or name:find("^<MouseMove") then
    return
  end
  if name:find("Mouse>") or name:find("^<%d?-?[%u]?%l*Mouse") then
    thaw(false)
  else
    thaw(true)
  end
end)

vim.keymap.set({ "n", "v" }, "m", "%")
vim.keymap.set("n", "vp", "viwp")

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
