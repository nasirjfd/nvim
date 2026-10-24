return {
  "NeogitOrg/neogit",
  lazy = true,
  dependencies = {
    "nvim-lua/plenary.nvim",
    -- Only one of these is needed.
    "nasirjfd/multi-repo-code-diff", -- optional (fork of esmuellert/codediff.nvim, same module)

    -- For a custom log pager
    "m00qek/baleia.nvim", -- optional

    -- Only one of these is needed.
    -- "nvim-telescope/telescope.nvim", -- optional
    -- "ibhagwan/fzf-lua", -- optional
    -- "nvim-mini/mini.pick", -- optional
    "folke/snacks.nvim", -- optional
  },
  cmd = "Neogit",
  opts = {
    disable_commit_confirmation = true,
  },
  keys = {
    {
      "<leader>gg",
      function()
        require("snacks").lazygit()
      end,
      desc = "Lazygit",
    },
  },
  config = function()
    require("neogit").setup({
      kind = "tab",
      diff_viewer = "codediff",
      integrations = {
        codediff = true,
      },
    })
  end,
}
-- return {}
