-- Database client: nvim-dbee (connections, SQL editor, paged results). Ours (lua/modules/database):
-- project connections from `.nvim.lua`, `e` on a result row edits it in a form.
return {
  {
    "kndndrj/nvim-dbee",
    dependencies = { "MunifTanjim/nui.nvim" },
    cmd = { "Dbee" },
    -- dbee downloads its Go backend asynchronously: wait for it, so a headless `Lazy install` (a new
    -- machine) does not quit before the binary is there.
    build = function()
      local bin = require("dbee.install").bin()
      require("dbee").install()
      vim.wait(300000, function()
        return vim.fn.executable(bin) == 1
      end, 200)
    end,
    keys = {
      {
        "<leader>D",
        function()
          require("dbee").toggle()
        end,
        desc = "Database (dbee)",
      },
      {
        "<leader>D",
        function()
          require("modules.database").run_selection()
        end,
        mode = "x",
        desc = "Run the selected SQL",
      },
    },
    config = function()
      require("modules.database").setup()
    end,
  },
}
