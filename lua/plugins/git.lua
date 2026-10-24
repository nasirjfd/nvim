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
    -- Fork of esmuellert/codediff.nvim with a multi-repo Source Control pane
    -- (:CodeDiff scm) and a Git Graph (:CodeDiff graph). The native library is
    -- still downloaded from the upstream release matching its VERSION file.
    "nasirjfd/multi-repo-code-diff",
    cmd = { "CodeDiff", "Codediff" },
    opts = {
      diff = {
        -- ]c / [c (and <F7> / <F19>) hop into the next/prev file at a file's last/first hunk
        cycle_hunks_across_files = true,
        -- <leader>hr discards the hunk immediately, without the "Discard hunk N?" prompt
        confirm_discard_hunk = false,
      },
      keymaps = {
        view = {
          quit = { "q", "<leader>dc" },
          next_hunk = { "]c", "<F7>" },
          prev_hunk = { "[c", "<F19>" },
        },
      },
    },
    config = function(_, opts)
      require("codediff").setup(opts)

      local group = vim.api.nvim_create_augroup("UserCodeDiff", { clear = true })

      -- Preview the file under the cursor as you move through the file list
      -- (no <CR> needed).
      local function preview_on_move(bufnr, panel)
        local last
        vim.api.nvim_create_autocmd("CursorMoved", {
          group = group,
          buffer = bufnr,
          callback = function()
            local view =
              require("codediff.ui.lifecycle").get_panel_view(vim.api.nvim_get_current_tabpage())
            local node = view and view.tree and view.tree:get_node()
            local data = node and node.data
            if not data or data == last then
              return
            end
            -- Explorer file rows carry no `type`; groups, folders and repositories do.
            local is_file = data.type == "file" or (panel == "explorer" and data.type == nil)
            if is_file then
              last = data
              view.on_file_select(data)
            end
          end,
        })
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = { "codediff-explorer", "codediff-history" },
        callback = function(args)
          -- <F7> / <F19> in the file list jumps back to the diff pane
          for _, lhs in ipairs({ "<F7>", "<F19>" }) do
            vim.keymap.set("n", lhs, "<cmd>wincmd p<cr>", { buffer = args.buf })
          end
          preview_on_move(args.buf, (args.match:gsub("^codediff%-", "")))
        end,
      })
    end,
    keys = {
      { "<leader>gvv", "<cmd>CodeDiff<cr>", desc = "Working Tree" },
      { "<leader>gvr", "<cmd>CodeDiff scm<cr>", desc = "All Repositories" },
      { "<leader>gvg", "<cmd>CodeDiff graph<cr>", desc = "Commit Graph" },
      { "<leader>gvs", "<cmd>CodeDiff --staged<cr>", desc = "Staged" },
      { "<leader>gvm", "<cmd>CodeDiff main...<cr>", desc = "Branch vs main" },
      { "<leader>gvf", "<cmd>CodeDiff file HEAD<cr>", desc = "Current File vs HEAD" },
      { "<leader>gvh", "<cmd>CodeDiff history<cr>", desc = "History" },
      { "<leader>gvH", "<cmd>CodeDiff history %<cr>", desc = "File History" },
      { "<leader>gvh", ":CodeDiff history<cr>", mode = "x", desc = "Selection History" },
    },
  },
  "tpope/vim-fugitive",
  "tpope/vim-rhubarb",
}
