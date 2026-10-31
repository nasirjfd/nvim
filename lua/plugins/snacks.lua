-- Called before a jump to a definition, reference or the like. In a codediff diff pane, go to the same
-- file in a full window of another tab first, so the target opens there, whole, instead of replacing a
-- pane of the diff.
local function outside_diff()
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  if lifecycle and lifecycle.get_session(vim.api.nvim_get_current_tabpage()) then
    require("codediff.ui.view.actions.panes").open_current_elsewhere()
  end
end

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
    backdrop = 60,
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
    { win = "list", height = 8, border = "none" }, -- few results, the preview gets the rest
    { win = "preview", title = "{preview}", border = "top" },
  },
}

return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  ---@type snacks.Config
  opts = {
    bigfile = { enabled = true },
    dashboard = { enabled = true },
    explorer = { enabled = true },
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
      -- Every picker: list on top, preview below, dimmed backdrop behind the modal
      layout = lsp_layout,
      actions = {
        -- Opening a file from a picker started in a codediff diff pane goes to a full window of
        -- another tab, so the diff (and the panel on its left) stays as it is.
        confirm = function(picker, item, action)
          local main = picker.main
          if main and vim.api.nvim_win_is_valid(main) then
            local lifecycle = package.loaded["codediff.ui.lifecycle"]
            local session = lifecycle and lifecycle.get_session(vim.api.nvim_win_get_tabpage(main))
            local buf = vim.api.nvim_win_get_buf(main)
            if session and (buf == session.original_bufnr or buf == session.modified_bufnr or buf == session.result_bufnr) then
              vim.api.nvim_set_current_win(main)
              if require("codediff.ui.view.actions.panes").open_current_elsewhere() then
                picker.main = vim.api.nvim_get_current_win()
              end
            end
          end
          Snacks.picker.actions.jump(picker, item, action)
        end,
      },
      win = {
        -- Close the picker on the first <Esc> instead of dropping to normal mode first
        -- <C-q> closes it too (snacks' default sends the results to the quickfix list and opens it)
        input = {
          keys = {
            ["<Esc>"] = { "close", mode = { "n", "i" } },
            ["<C-q>"] = { "close", mode = { "n", "i" } },
          },
        },
        list = { keys = { ["<C-q>"] = "close" } },
      },
      sources = {
        -- LSP location lists: only file:line, the code is already in the preview; list on top, preview below
        lsp_references = { format = "filename", layout = lsp_layout },
        lsp_definitions = { format = "filename", layout = lsp_layout },
        lsp_declarations = { format = "filename", layout = lsp_layout },
        lsp_implementations = { format = "filename", layout = lsp_layout },
        lsp_type_definitions = { format = "filename", layout = lsp_layout },
        files = {
          git_status = false,
          ignored = false,
          diagnostics = false,
          -- Rank recently-opened files to the top, even before typing anything.
          matcher = { frecency = true, sort_empty = true },
          -- PhpStorm style: file name first (bright), directory after it (dimmed)
          formatters = { file = { filename_first = true, truncate = "center" } },
        },
        gh_issue = {},
        gh_pr = {},
      },
    },
    quickfile = { enabled = true },
    scope = { enabled = true },
    scroll = { enabled = false },
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
        local cwd = vim.fn.getcwd()
        Snacks.picker.files({
          cwd = cwd,
          -- Ignored files stay hidden until <a-i> in the picker or <leader>uI
          ignored = vim.g.show_ignored == true,
          hidden = vim.g.show_ignored or false,
        })
      end,
      desc = "Find Files",
    },
    {
      "<leader>/",
      function()
        Snacks.picker.grep()
      end,
      desc = "Grep",
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
