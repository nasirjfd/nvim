-- ════════════════════════════════════════════════════════════════════════════
-- Multi-repo switcher — mirrors VSCode's git.scanRepositories for monorepos
-- with independent nested repos (e.g. Composer "path" packages checked out
-- under vendor/<vendor>/<package>, each with their own .git).
-- ════════════════════════════════════════════════════════════════════════════
local function has_git(path)
  return vim.uv.fs_stat(path .. "/.git") ~= nil
end

local function find_git_repos(root, max_depth)
  local repos = {}

  local function scan(dir, depth)
    if depth > max_depth then
      return
    end
    local handle = vim.uv.fs_scandir(dir)
    if not handle then
      return
    end
    while true do
      local name, typ = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if name ~= "node_modules" and name ~= ".git" then
        local path = dir .. "/" .. name
        if typ ~= "directory" then
          local stat = vim.uv.fs_stat(path)
          typ = stat and stat.type
        end
        if typ == "directory" then
          if has_git(path) then
            table.insert(repos, path) -- don't descend further into found repos
          else
            scan(path, depth + 1)
          end
        end
      end
    end
  end

  if has_git(root) then
    table.insert(repos, root)
  end
  scan(root, 1)

  table.sort(repos)
  return repos
end

--- Open a picker of git repos nested under cwd; `action(path)` runs on selection.
local function pick_repo(action)
  local root = vim.fn.getcwd()
  local repos = find_git_repos(root, 4)
  if #repos == 0 then
    vim.notify("No git repositories found under " .. root, vim.log.levels.WARN)
    return
  end

  Snacks.picker({
    title = "Git Repos",
    items = vim.tbl_map(function(path)
      local rel = path == root and "." or path:sub(#root + 2)
      return { text = rel, file = path }
    end, repos),
    format = "file",
    confirm = function(picker, item)
      picker:close()
      if item then
        action(item.file)
      end
    end,
    win = {
      input = {
        keys = {
          -- Open the selected repo in lazygit instead of Neogit
          -- (looked up via Snacks.picker.get since this key bypasses the
          -- picker-action wrapper and would otherwise receive the wrong object)
          ["<c-l>"] = {
            function()
              local picker = Snacks.picker.get({})[1]
              if not picker then
                return
              end
              local item = picker:current()
              picker:close()
              if item then
                Snacks.terminal.open("lazygit", {
                  cwd = item.file,
                  win = { position = "float", border = "rounded" },
                })
              end
            end,
            mode = { "n", "i" },
            desc = "Open in LazyGit",
          },
        },
      },
    },
  })
end

return {
  {
    "lewis6991/gitsigns.nvim",
    lazy = true,
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("gitsigns").setup({
        signs = {
          add = { text = "┃" },
          change = { text = "┃" },
          delete = { text = "_" },
          topdelete = { text = "‾" },
          changedelete = { text = "~" },
          untracked = { text = "┆" },
        },
        signs_staged = {
          add = { text = "┃" },
          change = { text = "┃" },
          delete = { text = "_" },
          topdelete = { text = "‾" },
          changedelete = { text = "~" },
          untracked = { text = "┆" },
        },
        signcolumn = true,
        numhl = false,
        linehl = false,
        word_diff = false,
        watch_gitdir = { interval = 1000, follow_files = true },
        attach_to_untracked = true,
        current_line_blame = false,
        current_line_blame_opts = {
          virt_text = true,
          virt_text_pos = "eol",
          delay = 1000,
          ignore_whitespace = false,
        },
        current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",
        sign_priority = 6,
        status_formatter = nil,
        update_debounce = 200,
        max_file_length = 40000,
        preview_config = {
          border = "rounded",
          style = "minimal",
          relative = "cursor",
          row = 0,
          col = 1,
        },
        on_attach = function(bufnr)
          local gs = require("gitsigns")
          local map = function(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
          end
          -- Navigation
          map("n", "]h", gs.next_hunk, "Next Hunk")
          map("n", "[h", gs.prev_hunk, "Prev Hunk")
          map("n", "<F7>", gs.next_hunk, "Next Hunk")
          map("n", "<F19>", gs.prev_hunk, "Prev Hunk")
        end,
      })
    end,
    keys = {
      -- Hunk operations under <leader>gh (git hunk)
      {
        "<leader>ghp",
        function()
          require("gitsigns").preview_hunk()
        end,
        desc = "Preview Hunk",
      },
      {
        "<leader>ghP",
        function()
          require("gitsigns").preview_hunk_inline()
        end,
        desc = "Preview Hunk Inline",
      },
      {
        "<leader>ghs",
        function()
          require("gitsigns").stage_hunk()
        end,
        desc = "Stage Hunk",
      },
      {
        "<leader>ghu",
        function()
          require("gitsigns").undo_stage_hunk()
        end,
        desc = "Undo Stage Hunk",
      },
      {
        "<leader>ghr",
        function()
          require("gitsigns").reset_hunk()
        end,
        desc = "Reset Hunk",
      },
      -- Buffer operations
      {
        "<leader>gR",
        function()
          require("gitsigns").reset_buffer()
        end,
        desc = "Reset Buffer",
      },
      {
        "<leader>gS",
        function()
          require("gitsigns").stage_buffer()
        end,
        desc = "Stage Buffer",
      },
      -- Blame
      {
        "<leader>gb",
        function()
          require("gitsigns").blame_line()
        end,
        desc = "Blame Line",
      },
      {
        "<leader>gB",
        function()
          require("gitsigns").blame()
        end,
        desc = "Blame Buffer",
      },
      -- Diff
      {
        "<leader>gD",
        function()
          vim.cmd("Gitsigns diffthis HEAD")
        end,
        desc = "Diff HEAD",
      },
      -- Switch repo (nested/vendor repos, see comment at top of file)
      {
        "<leader>gr",
        function()
          pick_repo(function(path)
            vim.cmd("cd " .. vim.fn.fnameescape(path))
            require("neogit").open({ cwd = path })
          end)
        end,
        desc = "Switch Repo",
      },
    },
  },
  {
    "sindrets/diffview.nvim",
    event = "VeryLazy",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles" },
  },
  {
    "sindrets/diffview.nvim",
    opts = {
      keymaps = {
        view = {
          {
            "n",
            "<F7>",
            function()
              local before = vim.api.nvim_win_get_cursor(0)
              vim.cmd.normal({ args = { "]c" }, bang = true })

              if vim.api.nvim_win_get_cursor(0)[1] == before[1] then
                local actions = require("diffview.actions")

                actions.select_next_entry()

                vim.schedule(function()
                  actions.focus_files()
                  actions.select_entry()
                end)
              end
            end,
          },
          {
            "n",
            "[c",
            function()
              local before = vim.api.nvim_win_get_cursor(0)
              vim.cmd.normal({ args = { "[c" }, bang = true })

              if vim.api.nvim_win_get_cursor(0)[1] == before[1] then
                local actions = require("diffview.actions")

                actions.select_prev_entry()

                vim.schedule(function()
                  actions.focus_files()
                  actions.select_entry()
                end)
              end
            end,
          },
        },
        file_panel = {
          {
            "n",
            "<F7>",
            function()
              vim.cmd.wincmd("p")
            end,
          },
          {
            "n",
            "<F19>",
            function()
              vim.cmd.wincmd("p")
            end,
          },
        },
      },
    },
  },
  "tpope/vim-fugitive",
  "tpope/vim-rhubarb",
}
