return {
  "folke/snacks.nvim",
  opts = {
    input = {
      win = {
        on_win = function(win)
          -- Input windows suppress autocmds and install their own maps last.
          vim.schedule(function()
            require("core.input-navigation").attach(win.buf, function()
              if win:valid() then
                win:execute("cancel")
              end
            end)
          end)
        end,
      },
    },
  },
}
