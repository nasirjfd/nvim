return {
  "folke/sidekick.nvim",
  version = "*",
  opts = {},
  keys = {
    {
      "<leader>ac",
      function()
        local State = require("sidekick.cli.state")
        local states = State.get({ name = "opencode" })
        local state = states[1]
        if not state then
          return
        end

        if state.attached and state.terminal then
          state.terminal:toggle()
          if state.terminal:is_open() and state.terminal:is_running() then
            state.terminal:focus()
          end
        else
          State.attach(state, { show = true, focus = true })
        end
      end,
      mode = { "n", "t" },
      desc = "Open OpenCode CLI",
    },
    {
      "<D-M-b>",
      function()
        require("sidekick.cli").toggle({ name = "opencode", focus = true })
      end,
      mode = { "n", "t" },
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
