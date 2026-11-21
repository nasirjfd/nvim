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
            -- text the prompt opens with is shown selected: typing replaces it
            if win:valid() and vim.api.nvim_get_current_buf() == win.buf then
              require("core.input-select").attach(win.buf)
            end
          end)
        end,
      },
    },
  },
}
