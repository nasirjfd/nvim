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
      { "<D-S-t>", function() require("modules.phpunit.pane").toggle() end, desc = "Tests pane" },
      { "<leader>ts", function() require("modules.phpunit.pane").toggle() end, desc = "Tests pane" },
      { "<leader>tt", function() require("modules.phpunit.runner").run_nearest() end, desc = "Run the test under the cursor" },
      { "<leader>tf", function() require("modules.phpunit.runner").run_file() end, desc = "Run the tests of this file" },
      { "<leader>ta", function() require("modules.phpunit.runner").run_all() end, desc = "Run all tests" },
      { "<leader>tF", function() require("modules.phpunit.runner").run_failed() end, desc = "Run the failed tests" },
      { "<leader>tl", function() require("modules.phpunit.runner").run_last() end, desc = "Run the last tests again" },
      { "<leader>tx", function() require("modules.phpunit.runner").stop() end, desc = "Stop the tests" },
      {
        "<leader>tp",
        function()
          local on = require("modules.phpunit.options").toggle_parallel()
          vim.notify("Tests in parallel: " .. (on and "on" or "off"), vim.log.levels.INFO, { title = "Tests" })
          for _, picker in ipairs(require("modules.phpunit.pane").panes()) do
            picker:find()
          end
        end,
        desc = "Run tests in parallel on/off",
      },
      { "<leader>to", function() require("neotest").output.open({ enter = true }) end, desc = "Test output" },
    },
    config = function()
      -- neotest reads the tests in a child Neovim that gets the runtimepath as it is now: the adapter's own
      -- plugin must be loaded (lazy.nvim loads it on its first require) before that
      require("neotest-phpunit")
      require("neotest").setup({
        adapters = { require("modules.phpunit").adapter },
        discovery = { enabled = true, concurrent = 4 },
        running = { concurrent = false }, -- the pane (modules/phpunit/runner.lua) decides what runs at once
        -- the tests pane is ours (modules/phpunit/pane.lua), fed by this consumer
        summary = { enabled = false },
        consumers = {
          phpunit_pane = function(client)
            require("modules.phpunit.pane").attach(client)
            return {}
          end,
        },
        output = { open_on_run = false },
        quickfix = { enabled = false },
      })
    end,
  },
}
