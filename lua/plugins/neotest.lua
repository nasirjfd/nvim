-- Tests: neotest (many languages through adapters) with its summary window as the tests pane (Cmd+Shift+T).
-- PHP runs through lua/modules/phpunit, which wraps olimorris/neotest-phpunit so a project can run PHPUnit
-- the way its editor config does (a command template, Docker paths): see the project's .nvim.lua.
return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter",
      "olimorris/neotest-phpunit",
    },
    cmd = "Neotest",
    keys = {
      { "<D-S-t>", function() require("modules.phpunit").toggle() end, desc = "Tests pane" },
      { "<leader>tt", function() require("neotest").run.run() end, desc = "Run nearest test" },
      { "<leader>tf", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Run tests of the file" },
      { "<leader>ta", function() require("neotest").run.run(vim.uv.cwd()) end, desc = "Run all tests" },
      { "<leader>tl", function() require("neotest").run.run_last() end, desc = "Run the last test again" },
      { "<leader>to", function() require("neotest").output.open({ enter = true }) end, desc = "Test output" },
      { "<leader>ts", function() require("modules.phpunit").toggle() end, desc = "Tests pane" },
    },
    config = function()
      -- neotest reads the tests in a child Neovim that gets the runtimepath as it is now: the adapter's own
      -- plugin must be loaded (lazy.nvim loads it on its first require) before that
      require("neotest-phpunit")
      require("neotest").setup({
        adapters = { require("modules.phpunit").adapter },
        discovery = { enabled = true, concurrent = 4 },
        summary = { follow = true, animated = true, open = "botright vsplit | vertical resize 60" },
        output = { open_on_run = false },
        quickfix = { enabled = false },
      })
    end,
  },
}
