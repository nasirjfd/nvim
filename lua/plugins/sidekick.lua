return {
  "folke/sidekick.nvim",
  version = "*",
  opts = {},
  keys = {
    {
      "<leader>ac",
      function()
        require("sidekick.cli").toggle({ name = "opencode", focus = true })
      end,
      desc = "Open OpenCode CLI",
    },
    {
      "<leader>af",
      function()
        require("sidekick.cli").send({ msg = "{file}" })
      end,
      desc = "Send File to OpenCode",
    },
    {
      "<leader>as",
      function()
        require("sidekick.cli").send({ msg = "{position}" })
      end,
      mode = "x",
      desc = "Send Selection Reference to OpenCode",
    },
  },
}
