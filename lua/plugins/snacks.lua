-- Called before a jump to a definition, reference or the like. In a codediff diff pane, go to the same
-- file in a full window of another tab first, so the target opens there, whole, instead of replacing a
-- pane of the diff.
local function outside_diff()
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  if lifecycle and lifecycle.get_session(vim.api.nvim_get_current_tabpage()) then
    require("codediff.ui.view.actions.panes").open_current_elsewhere()
  end
end

-- The explorer's "Explorer" title stays at the top while its search box is hidden: a plain centred
-- title (no border) in the explorer's top row. / shows the search box (which has the same title on
-- its border) in its place; Esc or opening a file brings the plain title back.
local EXPLORER_TITLE = "%#ExplorerTitle#%=Explorer%="

-- The title on the explorer's own background (a window header row is otherwise lighter grey)
local function explorer_title_colors()
  local bg = vim.api.nvim_get_hl(0, { name = "SnacksPickerList", link = false }).bg
  local fg = vim.api.nvim_get_hl(0, { name = "FloatTitle", link = false }).fg
  vim.api.nvim_set_hl(0, "ExplorerTitle", { bg = bg, fg = fg, bold = true })
end
explorer_title_colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = explorer_title_colors })

local function explorer_title(picker, on)
  local layout = picker.layout
  local root = layout and not layout.closed and layout.root
  if not (root and root.win and vim.api.nvim_win_is_valid(root.win)) then
    return
  end
  local winbar = on and EXPLORER_TITLE or ""
  vim.wo[root.win].winbar = winbar
  -- snacks re-applies its window options when the layout updates: keep the title in them
  root.opts.wo = root.opts.wo or {}
  root.opts.wo.winbar = winbar
end

-- Draw the title whenever an explorer list appears (opened, revealed, shown again).
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = vim.api.nvim_create_augroup("ExplorerTitle", { clear = true }),
  callback = function(args)
    if vim.bo[args.buf].filetype ~= "snacks_picker_list" then
      return
    end
    vim.schedule(function()
      for _, picker in ipairs(Snacks.picker.get({ source = "explorer" })) do
        if not picker.closed and picker.layout and picker.layout:is_hidden("input") then
          explorer_title(picker, true)
        end
      end
    end)
  end,
})

-- Jump straight to an LSP location. Duplicate locations (the same spot reported twice) are
-- collapsed; with several distinct ones, `first` jumps to the first and otherwise `fallback`
-- opens the picker. `on_self` runs instead of jumping when the target is the cursor's own line
-- (already on the definition).
local function lsp_goto(method, fallback, first, on_self)
  vim.lsp.buf[method]({
    on_list = function(res)
      local seen, items = {}, {}
      for _, item in ipairs(res.items) do
        local key = item.filename .. ":" .. item.lnum
        if not seen[key] then
          seen[key] = true
          items[#items + 1] = item
        end
      end
      if #items == 0 then
        return vim.notify("No " .. method .. " found", vim.log.levels.WARN)
      end
      if #items > 1 and not first then
        return fallback()
      end
      local item = items[1]
      if
        on_self
        and item.filename == vim.api.nvim_buf_get_name(0)
        and item.lnum == vim.api.nvim_win_get_cursor(0)[1]
      then
        return on_self()
      end
      vim.cmd("normal! m'")
      if vim.api.nvim_buf_get_name(0) ~= item.filename then
        vim.cmd.edit(vim.fn.fnameescape(item.filename))
      end
      vim.api.nvim_win_set_cursor(0, { item.lnum, item.col - 1 })
      vim.cmd("normal! zz")
    end,
  })
end

-- List on top, preview below. The vertical preset has no backdrop, so turn it on to dim the code
-- behind the picker.
local lsp_layout = {
  layout = {
    -- The dimmed backdrop sits below the explorer sidebar (its windows are at zindex 30-33), which
    -- is a float too: above it, the backdrop painted over the sidebar and it looked empty while a
    -- picker was open.
    backdrop = { blend = require("core.modal-backdrop").blend, win = { zindex = 20 } },
    row = 0.06, -- a little up from the center
    width = 0.7,
    min_width = 80,
    height = 0.88,
    min_height = 30,
    box = "vertical",
    border = true,
    title = "{title} {live} {flags}",
    title_pos = "center",
    { win = "input", height = 1, border = "bottom" },
    { win = "list", height = 12, border = "none" }, -- few results, the preview gets the rest
    { win = "preview", title = "{preview}", border = "top" },
  },
}

local builtin_layouts = {
  explorer = { preset = "sidebar", preview = false },
  select = { preset = "select" },
  command_history = { preset = "vscode" },
  search_history = { preset = "vscode" },
  icons = { preset = "vscode" },
  spelling = { preset = "vscode" },
  lines = { preset = "ivy", preview = "main" },
  gh_reactions = { preset = "select", layout = { max_width = 50 } },
  gh_labels = { preset = "select", layout = { max_width = 50 } },
  gh_actions = { preset = "select", layout = { max_width = 50 } },
}

-- A key typed during a smooth scroll (e.g. `zz` then `j`) would be undone: when the glide ends,
-- snacks.scroll restores the view it planned, cursor included. So finish the glide first: on any
-- typed key, run the running scroll animation's last step right away. (Registered here rather
-- than in the spec's `init`, which snacks-explorer-nested-git.lua's `init` replaces.)
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local ok, animate = pcall(require, "snacks.animate")
    if not ok then
      return
    end
    local scrolls = {} ---@type table<string, {anim: snacks.animate.Animation, cb: function, to: number}>
    local animate_add = animate.add
    animate.add = function(from, to, cb, anim_opts)
      local anim = animate_add(from, to, cb, anim_opts)
      local id = anim_opts and anim_opts.id
      if type(id) == "string" and id:find("^scroll") then
        scrolls[id] = { anim = anim, cb = cb, to = to }
      end
      return anim
    end
    vim.on_key(function(_, typed)
      if not typed or typed == "" then
        return -- keys the animation itself runs
      end
      for id, s in pairs(scrolls) do
        scrolls[id] = nil
        if s.anim.steps then -- still running
          s.anim:stop()
          pcall(s.cb, s.to, { anim = s.anim, prev = s.to, done = true })
        end
      end
    end, vim.api.nvim_create_namespace("finish_scroll_on_key"))
  end,
})

-- The explorer learns which entries git ignores from an asynchronous `git status`, so it used to
-- list everything (ignored folders, build output) for a moment and only then drop them, which looked
-- like the first `h` / `l` "fixing" the list. Two things prevent that: the status is fetched ahead of
-- time (at startup and after every directory change), and if it is still not in when the explorer
-- opens, opening waits for it (at most 1.5 s) so the very first list is the right one.
vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
  group = vim.api.nvim_create_augroup("ExplorerGitWarm", { clear = true }),
  callback = function(ev)
    vim.schedule(function()
      local ok, git = pcall(require, "snacks.explorer.git")
      if ok then
        pcall(git.update, vim.fn.getcwd(), { untracked = true })
      end
      if ev.event == "VimEnter" then
        -- after the nested-repo patch (snacks-explorer-nested-git.lua) has wrapped the git module
        vim.schedule(function()
          local ok_explorer, explorer = pcall(require, "snacks.explorer")
          if not ok_explorer or explorer._waits_for_git then
            return
          end
          explorer._waits_for_git = true
          local open = explorer.open
          explorer.open = function(opts)
            local cwd = vim.fs.normalize((opts and opts.cwd) or vim.fn.getcwd())
            _G.explorer_git_ready = _G.explorer_git_ready or {}
            if not _G.explorer_git_ready[cwd] then
              pcall(require("snacks.explorer.git").update, cwd, { untracked = true })
              vim.wait(1500, function()
                return _G.explorer_git_ready[cwd] == true
              end, 10)
            end
            return open(opts)
          end
        end)
      end
    end)
  end,
})

-- Opening a directory shows the explorer on it (what snacks' `replace_netrw` does), but through the
-- patched `open`, which first waits for the git status: with `nvim .` in vendor/ the explorer used
-- to appear with every folder of the directory (117 entries) and only the 3 un-ignored ones after the
-- first `h` / `l` made it redraw.
vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("ExplorerGitWarm", { clear = false }),
  callback = function()
    vim.schedule(function()
      pcall(vim.api.nvim_del_augroup_by_name, "FileExplorer") -- netrw
      local group = vim.api.nvim_create_augroup("ExplorerOpenDirectory", { clear = true })
      local function handle(ev)
        if ev.file ~= "" and vim.fn.isdirectory(ev.file) == 1 then
          -- The open patch above is installed one tick after this handler on startup, so wait for the
          -- git status here too -- without blocking: a blocking wait lets UIEnter run in the middle of
          -- startup (E823 "Not an undo file: .../undo/." for the directory buffer).
          local cwd = vim.fs.normalize(ev.file)
          _G.explorer_git_ready = _G.explorer_git_ready or {}
          local function open()
            if not vim.api.nvim_buf_is_valid(ev.buf) then
              return
            end
            local picker = Snacks.explorer.open({ cwd = ev.file })
            -- The directory buffer must never be (re)loaded: with 'undofile' that tries to read an
            -- undo file named after the directory (E823 "Not an undo file: .../undo/." in UIEnter).
            pcall(function()
              vim.bo[ev.buf].undofile = false
              vim.api.nvim_buf_set_name(ev.buf, "")
            end)
            Snacks.bufdelete.delete(ev.buf)
            if picker then
              vim.schedule(function()
                if not picker.closed then
                  picker:focus()
                end
              end)
            end
          end
          if _G.explorer_git_ready[cwd] then
            open()
            return
          end
          pcall(require("snacks.explorer.git").update, cwd, { untracked = true })
          local waited = 0
          local function poll()
            waited = waited + 10
            if _G.explorer_git_ready[cwd] or waited >= 1500 then
              open()
            else
              vim.defer_fn(poll, 10)
            end
          end
          vim.defer_fn(poll, 10)
        end
      end
      -- the directory given on the command line is already the current buffer
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(buf)
        if name ~= "" and vim.fn.isdirectory(name) == 1 then
          handle({ file = name, buf = buf })
          break
        end
      end
      vim.api.nvim_create_autocmd("BufEnter", { group = group, callback = handle })
    end)
  end,
})

return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  ---@type snacks.Config
  opts = {
    bigfile = { enabled = true },
    dashboard = { enabled = true },
    -- replace_netrw is off: opening a directory (`nvim .`, `:e dir`) is handled below, so that it goes
    -- through the same wait for the git status as every other way of opening the explorer
    explorer = { enabled = true, replace_netrw = false },
    image = {
      enabled = true,
      doc = {
        enabled = true,
        inline = true,
        float = true,
        max_width = 80,
        max_height = 40,
      },
    },
    indent = { enabled = false },
    input = { enabled = true },
    notifier = { enabled = true, timeout = 3000, width = { min = 40, max = 0.6 }, height = { min = 1, max = 0.8 } }, -- wide and tall enough that a long message (git output, a commit message) shows whole
    picker = {
      enabled = true,
      -- Every picker: list on top, preview below, dimmed backdrop behind the modal. Pickers that
      -- are not file lists (explorer sidebar, select popups, vscode-style command lists) keep
      -- their built-in layout.
      -- PhpStorm style in every list: file name first (bright), directory after it (dimmed)
      formatters = { file = { filename_first = true, truncate = "center" } },
      layout = function(source)
        return builtin_layouts[source] or lsp_layout
      end,
      actions = {
        -- Opening a file from a picker started in a codediff diff pane goes to a full window of
        -- another tab, so the diff (and the panel on its left) stays as it is.
        -- <Esc> closes the picker, unless a <BS> follows right away: some terminals deliver
        -- Option+Backspace as <Esc><BS>, which should delete the previous word instead.
        close_or_delete_word = function(picker)
          -- Option+Backspace may reach Neovim as <Esc> and, a little later (herdr relays it in two
          -- pieces), <BS>: give the second half time to arrive before treating this as "close"
          vim.wait(120, function()
            return vim.fn.getchar(1) ~= 0
          end, 5)
          if vim.fn.getchar(1) ~= 0 then
            local key = vim.fn.getchar(0)
            if type(key) == "string" and vim.fn.keytrans(key) == "<BS>" or key == 127 then
              local col = vim.api.nvim_win_get_cursor(0)[2]
              local before = vim.api.nvim_get_current_line():sub(1, col)
              local kept = before:gsub("%s+$", ""):gsub("[%w_]+$", ""):gsub("[^%w_%s]+$", "")
              vim.api.nvim_buf_set_text(0, 0, #kept, 0, col, {})
              vim.api.nvim_win_set_cursor(0, { 1, #kept })
              return
            end
            vim.api.nvim_feedkeys(type(key) == "number" and vim.fn.nr2char(key) or key, "t", false)
          end
          picker:close()
        end,
        confirm = function(picker, item, action)
          -- picked in the git pane or another codediff tab: open it in an editor tab instead of a
          -- pane of the diff (core/leave-codediff.lua)
          local target = require("core.leave-codediff").editor_window(picker.main)
          if target then
            picker.main = target
          end
          Snacks.picker.actions.jump(picker, item, action)
        end,
      },
      win = {
        -- Close the picker on the first <Esc> instead of dropping to normal mode first
        -- <C-q> closes it too (snacks' default sends the results to the quickfix list and opens it)
        input = {
          keys = {
            ["<Esc>"] = { "close_or_delete_word", mode = { "n", "i" } },
            ["<C-q>"] = { "close", mode = { "n", "i" } },
          },
        },
        list = { keys = { ["<C-q>"] = "close" } },
      },
      sources = {
        -- Global grep: case-insensitive, plain text; buttons in the search box toggle case / word / regex
        grep = {
          regex = false,
          args = { "--ignore-case" },
          toggles = { regex = false }, -- the title's "R" flag: the regex button replaces it
          on_show = function(picker)
            require("core.grep-toggles").attach(picker)
          end,
        },
        -- LSP location lists: only file:line, the code is already in the preview; list on top, preview below
        lsp_references = { format = "filename", layout = lsp_layout },
        lsp_definitions = { format = "filename", layout = lsp_layout },
        lsp_declarations = { format = "filename", layout = lsp_layout },
        lsp_implementations = { format = "filename", layout = lsp_layout },
        lsp_type_definitions = { format = "filename", layout = lsp_layout },
        -- Recent files: v:oldfiles also keeps directories (the explorer and `nvim .` open them as
        -- buffers), which showed up as a row without a file name
        recent = {
          matcher = { -- case never matters, ranked like files
            smartcase = false,
            ignorecase = true,
            on_match = function(...)
              require("core.file-rank").on_match(...)
            end,
          },
          transform = function(item)
            local file = item.file
            if type(file) ~= "string" or file == "" or file:sub(-1) == "/" or vim.fn.isdirectory(file) == 1 then
              return false
            end
          end,
        },
        files = {
          git_status = false,
          ignored = false,
          diagnostics = false,
          -- Rank recently-opened files to the top, even before typing anything. Case never matters
          -- (no smartcase): POST also finds PostController.php, the whole word ranked above P…O…S…T.
          matcher = {
            frecency = true,
            sort_empty = true,
            smartcase = false,
            ignorecase = true,
            -- JetBrains-like: pprecord ranks ParcelProjectionRecord first (core/file-rank.lua)
            on_match = function(...)
              require("core.file-rank").on_match(...)
            end,
          },
        },
        explorer = {
          -- the search box is hidden until / (Esc, or opening a file from it, hides it again)
          layout = { preset = "sidebar", preview = false, hidden = { "input" } },
          actions = {
            -- Cmd+V in the explorer: paste the copied files into the directory under the cursor. A
            -- file pasted into the folder it came from (or onto a name that exists) asks for the new
            -- name first, with the current name filled in, like JetBrains.
            -- <C-q> in the explorer quits Neovim, as in every other window (the pickers' <C-q> only
            -- closes the picker, which left a blank buffer and needed a second <C-q>)
            quit_nvim = function()
              vim.cmd("confirm qa")
            end,
            -- `r`: the name box opens with the cursor before the extension (nothing selected)
            explorer_rename = function(picker, item)
              require("snacks.explorer.actions").actions.explorer_rename(picker, item)
              vim.schedule(function()
                local win = vim.api.nvim_get_current_win()
                if vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "snacks_input" then
                  return
                end
                local text = vim.api.nvim_get_current_line()
                local name = text:match("[^/]*$") or text
                local stem = name:match("^(.+)%.[^.]+$")
                if stem then
                  pcall(vim.api.nvim_win_set_cursor, win, { 1, #text - #name + #stem })
                end
              end)
            end,
            explorer_paste_named = function(picker)
              local Tree = require("snacks.explorer.tree")
              local Actions = require("snacks.explorer.actions")
              local files = vim.tbl_filter(function(file)
                return file ~= "" and (vim.fn.filereadable(file) == 1 or vim.fn.isdirectory(file) == 1)
              end, vim.split(vim.fn.getreg("+") or "", "\n", { plain = true }))
              if #files == 0 then
                return Snacks.notify.warn("Nothing copied: copy a file in the explorer with Cmd+C first")
              end
              local dir = vim.fs.normalize(picker:dir())
              local last
              local function finish()
                Tree:refresh(dir)
                Tree:open(dir)
                Actions.update(picker, { target = last or dir })
              end
              local function paste(index)
                local from = files[index]
                if not from then
                  return finish()
                end
                from = vim.fs.normalize(from)
                local name = vim.fn.fnamemodify(from, ":t")
                local function copy(new_name)
                  last = dir .. "/" .. new_name
                  Snacks.picker.util.copy_path(from, last)
                  paste(index + 1)
                end
                if vim.fs.dirname(from) == dir or vim.uv.fs_stat(dir .. "/" .. name) then
                  local input = Snacks.input({
                    prompt = "Paste as",
                    default = name,
                  }, function(value)
                    value = value and vim.trim(value)
                    if not value or value == "" then
                      return finish()
                    end
                    copy(value)
                  end)
                  -- The name before the extension is selected (Select mode): typing replaces it and
                  -- the extension stays, as in JetBrains
                  local stem = name:match("^(.+)%.[^.]+$")
                  if stem and input and input.win then
                    vim.schedule(function()
                      if not vim.api.nvim_win_is_valid(input.win) then
                        return
                      end
                      -- Enter must also confirm while the name is selected (Select mode)
                      vim.keymap.set("s", "<CR>", function()
                        input:execute("confirm")
                      end, { buffer = input.buf })
                      vim.api.nvim_win_call(input.win, function()
                        vim.cmd("stopinsert")
                        vim.api.nvim_win_set_cursor(0, { 1, 0 })
                        local more = vim.fn.strchars(stem) - 1
                        vim.cmd("normal! v" .. (more > 0 and (more .. "l") or ""))
                        vim.api.nvim_feedkeys(vim.keycode("<C-g>"), "n", false)
                      end)
                    end)
                  end
                else
                  copy(name)
                end
              end
              paste(1)
            end,
            -- Enter in the explorer's search box opens the first matching *file* and moves the cursor
            -- into it (the matches list starts with their parent directories, so a plain confirm
            -- would only expand a folder, and the cursor would stay in the explorer)
            search_confirm = function(picker)
              local item = picker:current()
              if picker.input.filter.pattern ~= "" and (not item or item.dir) then
                for i = 1, picker.list:count() do
                  local it = picker.list:get(i)
                  if it and not it.dir then
                    item = it
                    break
                  end
                end
              end
              if not item or item.dir then
                return picker:action("confirm")
              end
              -- the explorer stays open after opening a file, so also move the cursor into the file
              Snacks.picker.actions.jump(picker, item, { cmd = "edit" })
              if vim.api.nvim_win_is_valid(picker.main) then
                vim.api.nvim_set_current_win(picker.main)
              end
              -- clear the search, so the explorer shows the full tree again (with the file revealed)
              vim.schedule(function()
                if not picker.closed then
                  picker.input:set("", "")
                  picker:find()
                  picker:toggle("input", { enable = false })
                  explorer_title(picker, true)
                end
              end)
            end,
            -- / in the list: show the search box (in place of the plain title) and type in it
            show_search = function(picker)
              explorer_title(picker, false)
              picker:toggle("input", { enable = true, focus = true })
              -- an earlier search stays in the box: select it, so typing replaces it (like a text field)
              vim.schedule(function()
                if picker.closed or picker.input:get() == "" then
                  return
                end
                if vim.api.nvim_get_current_win() == picker.input.win.win then
                  vim.api.nvim_feedkeys(vim.keycode("<Esc>$v0<C-g>"), "n", false)
                end
              end)
            end,
            -- Esc in the search box: clear it, hide it, back to the list
            hide_search = function(picker)
              vim.cmd("stopinsert")
              picker.input:set("", "")
              picker:find()
              picker:toggle("input", { enable = false })
              explorer_title(picker, true)
              picker:focus("list")
            end,
          },
          win = {
            input = {
              keys = {
                ["<CR>"] = { "search_confirm", mode = { "n", "i" } },
                ["<Esc>"] = { "hide_search", mode = { "n", "i" } },
                ["<C-q>"] = { "quit_nvim", mode = { "n", "i" } },
              },
            },
            list = {
              keys = {
                ["<C-q>"] = "quit_nvim",
                ["/"] = "show_search",
                ["<D-c>"] = { "explorer_yank", mode = { "n", "x" } },
                ["<D-v>"] = "explorer_paste_named",
              },
            },
          },
        },
        gh_issue = {},
        gh_pr = {},
      },
    },
    quickfile = { enabled = true },
    scope = { enabled = true },
    -- Keyboard scrolls and jumps (Ctrl+d/u, G, search, gd, …) land almost at once and settle with a
    -- short ease-out. Each frame moves as many lines as the curve needs in one redraw, and a new
    -- press restarts from where the view is, so it never trails behind. Trackpad/mouse scrolling
    -- is not animated (see mousescroll in core/options.lua).
    scroll = {
      enabled = true,
      -- No glide while a picker is open: its preview jumps between files and lines as the selection
      -- moves (LSP references, grep...), and animating that only gets in the way.
      filter = function(buf)
        if vim.g.snacks_scroll == false or vim.b[buf].snacks_scroll == false or vim.bo[buf].buftype == "terminal" then
          return false
        end
        local ok, pickers = pcall(function()
          return Snacks.picker.get()
        end)
        return not (ok and pickers and #pickers > 0)
      end,
      animate = { duration = { step = 6, total = 110 }, easing = "outCubic" },
      -- presses within 100ms of the last one (holding a key) get an even shorter glide
      animate_repeat = { delay = 100, duration = { step = 3, total = 40 }, easing = "outCubic" },
    },
    statuscolumn = { enabled = true },
    words = { enabled = true },
    styles = { notification = {} },
    gh = {},
  },
  keys = {
    -- ════════════════════════════════════════════════════════════════════
    -- Top-level (most used - quick access)
    -- ════════════════════════════════════════════════════════════════════
    {
      "<leader><space>",
      function()
        -- Opens from a cached file list (see core/file-cache.lua)
        Snacks.picker.files(require("core.file-cache").opts())
      end,
      desc = "Find Files",
    },
    -- With a selection: the files picker starts with the selected text (first line) in its search
    -- box, editable like any typed search
    {
      "<leader><space>",
      function()
        local text = table.concat(vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() }), "\n")
        vim.cmd("normal! \27")
        Snacks.picker.files(vim.tbl_extend("force", require("core.file-cache").opts() or {}, { pattern = text:match("^[^\n]*") }))
      end,
      mode = "x",
      desc = "Find Files (selection)",
    },
    {
      "<leader>/",
      function()
        Snacks.picker.grep()
      end,
      desc = "Grep",
    },
    -- Grep with the current visual selection typed into the search (single line); plain grep otherwise
    {
      "<leader>/",
      function()
        local text = table.concat(vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() }), "\n")
        vim.cmd("normal! \27")
        Snacks.picker.grep({ search = text:match("^[^\n]*"), live = true })
      end,
      mode = "x",
      desc = "Grep selection",
    },
    {
      "<D-S-f>",
      function()
        Snacks.picker.grep()
      end,
      desc = "Grep",
    },
    {
      "<D-S-f>",
      function()
        local text = table.concat(vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() }), "\n")
        vim.cmd("normal! \27")
        Snacks.picker.grep({ search = text:match("^[^\n]*"), live = true })
      end,
      mode = "x",
      desc = "Grep selection",
    },
    {
      "<D-F>",
      function()
        local text = table.concat(vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() }), "\n")
        vim.cmd("normal! \27")
        Snacks.picker.grep({ search = text:match("^[^\n]*"), live = true })
      end,
      mode = "x",
      desc = "Grep selection",
    },
    {
      "<leader>.",
      function()
        Snacks.scratch()
      end,
      desc = "Scratch Buffer",
    },
    {
      "<leader>e",
      function()
        Snacks.explorer()
      end,
      desc = "Explorer",
    },
    {
      "<leader>,",
      function()
        Snacks.picker.buffers()
      end,
      desc = "Buffers",
    },

    -- Terminal
    {
      "<C-/>",
      function()
        Snacks.terminal()
      end,
      desc = "Terminal",
    },
    {
      "<C-_>",
      function()
        Snacks.terminal()
      end,
      desc = "which_key_ignore",
    },

    -- Word navigation (LSP references)
    {
      "]]",
      function()
        Snacks.words.jump(vim.v.count1)
      end,
      desc = "Next Reference",
      mode = { "n", "t" },
    },
    {
      "[[",
      function()
        Snacks.words.jump(-vim.v.count1)
      end,
      desc = "Prev Reference",
      mode = { "n", "t" },
    },

    -- ════════════════════════════════════════════════════════════════════
    -- <leader>b = Buffers
    -- ════════════════════════════════════════════════════════════════════
    {
      "<leader>bb",
      function()
        Snacks.picker.buffers({
          win = {
            input = {
              keys = { ["dd"] = "bufdelete", ["<C-d>"] = { "bufdelete", mode = { "n", "i" } } },
            },
            list = { keys = { ["dd"] = "bufdelete" } },
          },
        })
      end,
      desc = "Switch Buffer",
    },
    {
      "<leader>bd",
      function()
        Snacks.bufdelete()
      end,
      desc = "Delete Buffer",
    },
    {
      "<leader>bo",
      function()
        Snacks.bufdelete.other()
      end,
      desc = "Delete Other Buffers",
    },
    {
      "Q",
      function()
        Snacks.bufdelete()
      end,
      desc = "Delete Buffer",
    },

    -- ════════════════════════════════════════════════════════════════════
    -- <leader>c = Code
    -- ════════════════════════════════════════════════════════════════════
    -- ca (code action) - defined in lsp.lua
    -- cf (format) - defined in formatting.lua
    -- cr (rename symbol) - defined in lsp.lua
    -- cd (line diagnostic) - defined in lsp.lua

    -- ════════════════════════════════════════════════════════════════════
    -- <leader>d = Diagnostics
    -- ════════════════════════════════════════════════════════════════════
    {
      "<leader>dd",
      function()
        Snacks.picker.diagnostics()
      end,
      desc = "Workspace Diagnostics",
    },
    {
      "<leader>db",
      function()
        Snacks.picker.diagnostics_buffer()
      end,
      desc = "Buffer Diagnostics",
    },
    {
      "<leader>dq",
      function()
        Snacks.picker.qflist()
      end,
      desc = "Quickfix List",
    },
    {
      "<leader>dl",
      function()
        Snacks.picker.loclist()
      end,
      desc = "Location List",
    },

    -- ════════════════════════════════════════════════════════════════════
    -- <leader>f = Files
    -- ════════════════════════════════════════════════════════════════════
    {
      "<leader>ff",
      function()
        Snacks.picker.files()
      end,
      desc = "Find Files",
    },
    {
      "<leader>fr",
      function()
        Snacks.picker.recent()
      end,
      desc = "Recent Files",
    },
    {
      "<leader>fc",
      function()
        Snacks.picker.files({ cwd = vim.fn.stdpath("config") })
      end,
      desc = "Config Files",
    },
    {
      "<leader>fg",
      function()
        Snacks.picker.git_files()
      end,
      desc = "Git Files",
    },
    {
      "<leader>fp",
      function()
        Snacks.picker.projects()
      end,
      desc = "Projects",
    },
    {
      "<leader>fR",
      function()
        Snacks.rename.rename_file()
      end,
      desc = "Rename File",
    },

    -- ════════════════════════════════════════════════════════════════════
    -- <leader>g = Git
    -- ════════════════════════════════════════════════════════════════════
    -- {
    --   "<leader>gg",
    --   function()
    --     Snacks.lazygit()
    --   end,
    --   desc = "Lazygit",
    -- },
    {
      "<leader>gl",
      function()
        Snacks.picker.git_log()
      end,
      desc = "Log",
    },
    {
      "<leader>gL",
      function()
        Snacks.picker.git_log_line()
      end,
      desc = "Log (line)",
    },
    {
      "<leader>gf",
      function()
        Snacks.picker.git_log_file()
      end,
      desc = "Log (file)",
    },
    {
      "<leader>gs",
      function()
        Snacks.picker.git_status()
      end,
      desc = "Status",
    },
    {
      "<leader>gS",
      function()
        Snacks.picker.git_stash()
      end,
      desc = "Stash",
    },
    {
      "<leader>gd",
      function()
        Snacks.picker.git_diff()
      end,
      desc = "Diff (picker)",
    },
    {
      "<leader>gc",
      function()
        Snacks.picker.git_branches()
      end,
      desc = "Checkout Branch",
    },
    {
      "<leader>go",
      function()
        Snacks.gitbrowse()
      end,
      desc = "Open in Browser",
      mode = { "n", "v" },
    },
    -- GitHub
    {
      "<leader>gi",
      function()
        Snacks.picker.gh_issue()
      end,
      desc = "Issues",
    },
    {
      "<leader>gI",
      function()
        Snacks.picker.gh_issue({ state = "all" })
      end,
      desc = "Issues (all)",
    },
    -- {
    --   "<leader>gp",
    --   function()
    --     Snacks.picker.gh_pr()
    --   end,
    --   desc = "Pull Requests",
    -- },
    {
      "<leader>gP",
      function()
        Snacks.picker.gh_pr({ state = "all" })
      end,
      desc = "Pull Requests (all)",
    },
    -- Hunk operations defined in git.lua: gh, ga, gu, gr, gR, gB, gD

    -- ════════════════════════════════════════════════════════════════════
    -- <leader>l = LSP
    -- ════════════════════════════════════════════════════════════════════
    {
      "<leader>ls",
      function()
        Snacks.picker.lsp_symbols()
      end,
      desc = "Document Symbols",
    },
    {
      "<leader>lS",
      function()
        Snacks.picker.lsp_workspace_symbols()
      end,
      desc = "Workspace Symbols",
    },
    -- li (info), lr (restart), lh (hints) - defined in lsp.lua

    -- ════════════════════════════════════════════════════════════════════
    -- <leader>n = Notifications
    -- ════════════════════════════════════════════════════════════════════
    {
      "<leader>nn",
      function()
        Snacks.notifier.show_history()
      end,
      desc = "Notification History",
    },
    {
      "<leader>nd",
      function()
        Snacks.notifier.hide()
      end,
      desc = "Dismiss All",
    },

    -- ════════════════════════════════════════════════════════════════════
    -- <leader>s = Search
    -- ════════════════════════════════════════════════════════════════════
    {
      "<leader>sg",
      function()
        Snacks.picker.grep()
      end,
      desc = "Grep",
    },
    {
      "<leader>sw",
      function()
        Snacks.picker.grep_word()
      end,
      desc = "Word",
      mode = { "n", "x" },
    },
    {
      "<leader>sb",
      function()
        Snacks.picker.lines()
      end,
      desc = "Buffer Lines",
    },
    {
      "<leader>sB",
      function()
        Snacks.picker.grep_buffers()
      end,
      desc = "Grep Buffers",
    },
    {
      "<leader>sh",
      function()
        Snacks.picker.help()
      end,
      desc = "Help",
    },
    {
      "<leader>sm",
      function()
        Snacks.picker.marks()
      end,
      desc = "Marks",
    },
    {
      "<leader>sj",
      function()
        Snacks.picker.jumps()
      end,
      desc = "Jumps",
    },
    {
      "<leader>sk",
      function()
        Snacks.picker.keymaps()
      end,
      desc = "Keymaps",
    },
    {
      "<leader>sc",
      function()
        Snacks.picker.commands()
      end,
      desc = "Commands",
    },
    {
      "<leader>s:",
      function()
        Snacks.picker.command_history()
      end,
      desc = "Command History",
    },
    {
      "<leader>s/",
      function()
        Snacks.picker.search_history()
      end,
      desc = "Search History",
    },
    {
      "<leader>sr",
      function()
        Snacks.picker.registers()
      end,
      desc = "Registers",
    },
    {
      "<leader>sR",
      function()
        Snacks.picker.resume()
      end,
      desc = "Resume Last",
    },
    {
      "<leader>su",
      function()
        Snacks.picker.undo()
      end,
      desc = "Undo History",
    },
    {
      "<leader>sM",
      function()
        Snacks.picker.man()
      end,
      desc = "Man Pages",
    },
    {
      "<leader>si",
      function()
        Snacks.picker.icons()
      end,
      desc = "Icons",
    },

    -- ════════════════════════════════════════════════════════════════════
    -- <leader>u = UI / Toggles
    -- ════════════════════════════════════════════════════════════════════
    {
      "<leader>uC",
      function()
        Snacks.picker.colorschemes()
      end,
      desc = "Colorschemes",
    },
    {
      "<leader>uz",
      function()
        Snacks.zen()
      end,
      desc = "Zen Mode",
    },
    {
      "<leader>uZ",
      function()
        Snacks.zen.zoom()
      end,
      desc = "Zoom",
    },
    {
      "<leader>uN",
      function()
        Snacks.win({
          file = vim.api.nvim_get_runtime_file("doc/news.txt", false)[1],
          width = 0.6,
          height = 0.6,
          wo = {
            spell = false,
            wrap = false,
            signcolumn = "yes",
            statuscolumn = " ",
            conceallevel = 3,
          },
        })
      end,
      desc = "Neovim News",
    },
    -- Other toggles defined in init function below

    -- ════════════════════════════════════════════════════════════════════
    -- <leader>w = Windows (verbose, but useful for discoverability)
    -- ════════════════════════════════════════════════════════════════════
    { "<leader>wd", "<C-w>c", desc = "Close Window" },
    { "<leader>ws", "<C-w>s", desc = "Split Horizontal" },
    { "<leader>wv", "<C-w>v", desc = "Split Vertical" },
    { "<leader>ww", "<C-w>w", desc = "Other Window" },
    { "<leader>w=", "<C-w>=", desc = "Equal Size" },
    {
      "<leader>wm",
      function()
        Snacks.zen.zoom()
      end,
      desc = "Maximize",
    },

    -- ════════════════════════════════════════════════════════════════════
    -- g = Goto (LSP navigation via Snacks picker)
    -- ════════════════════════════════════════════════════════════════════
    {
      "gd",
      function()
        outside_diff()
        -- On a usage: jump to the definition. Already on the definition: list its usages
        -- (a single usage is opened directly).
        lsp_goto("definition", function()
          Snacks.picker.lsp_definitions()
        end, true, function()
          Snacks.picker.lsp_references({ include_declaration = false })
        end)
      end,
      desc = "Definition",
    },
    {
      "gD",
      function()
        outside_diff()
        Snacks.picker.lsp_declarations()
      end,
      desc = "Declaration",
    },
    {
      "gr",
      function()
        outside_diff()
        Snacks.picker.lsp_references()
      end,
      nowait = true,
      desc = "References",
    },
    {
      "gi",
      function()
        outside_diff()
        lsp_goto("implementation", function()
          Snacks.picker.lsp_implementations()
        end)
      end,
      desc = "Implementation",
    },
    {
      "gy",
      function()
        outside_diff()
        Snacks.picker.lsp_type_definitions()
      end,
      desc = "Type Definition",
    },
  },
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      callback = function()
        -- Debug globals
        _G.dd = function(...)
          Snacks.debug.inspect(...)
        end
        _G.bt = function()
          Snacks.debug.backtrace()
        end
        vim.print = _G.dd

        -- Toggle mappings under <leader>u
        Snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>us")
        Snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
        Snacks.toggle.option("relativenumber", { name = "Relative Number" }):map("<leader>ur")
        Snacks.toggle.line_number():map("<leader>ul")
        Snacks.toggle.diagnostics():map("<leader>uD")
        Snacks.toggle
          .option("conceallevel", { off = 0, on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2 })
          :map("<leader>uc")
        Snacks.toggle.treesitter():map("<leader>uT")
        Snacks.toggle
          .option("background", { off = "light", on = "dark", name = "Dark Background" })
          :map("<leader>ub")
        Snacks.toggle.inlay_hints():map("<leader>uh")
        Snacks.toggle.indent():map("<leader>ui")
        Snacks.toggle.dim():map("<leader>ud")

        Snacks.toggle({
          name = "Autosave",
          get = function()
            return vim.g.autosave == true
          end,
          set = function(state)
            vim.g.autosave = state
          end,
        }):map("<leader>uA")

        -- Show/search ignored (and hidden) files in the explorer and every file/grep picker
        Snacks.toggle({
          name = "Ignored Files",
          get = function()
            return vim.g.show_ignored == true
          end,
          set = function(state)
            vim.g.show_ignored = state
            local sources = Snacks.config.picker.sources
            for _, source in ipairs({ "files", "grep", "grep_word", "grep_buffers", "explorer" }) do
              sources[source] = sources[source] or {}
              sources[source].ignored = state
              sources[source].hidden = state
            end
            -- Apply to pickers that are already open (e.g. the explorer sidebar)
            for _, picker in ipairs(Snacks.picker.get()) do
              picker.opts.ignored = state
              picker.opts.hidden = state
              picker:find()
            end
          end,
        }):map("<leader>uI")
      end,
    })
  end,
}
