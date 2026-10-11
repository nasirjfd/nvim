return {
  "folke/sidekick.nvim",
  version = "*",
  opts = {},
  keys = {
    {
      "<leader>ac",
      function()
        require("sidekick.cli").toggle({ name = "codex", focus = true })
      end,
      desc = "Open Codex CLI",
    },
    {
      "<leader>af",
      function()
        require("sidekick.cli").send({ msg = "{file}" })
      end,
      desc = "Send File to Codex",
    },
    {
      "<leader>as",
      function()
        require("sidekick.cli").send({ msg = "{selection}" })
      end,
      mode = "x",
      desc = "Send Selection to Codex",
    },
  },
}
