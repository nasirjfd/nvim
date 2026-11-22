return {
  "folke/snacks.nvim",
  opts = {
    input = {
      win = {
        keys = {
          -- Enter as a plain mapping. Snacks' own is an expression mapping that confirms while its expression is
          -- evaluated, and Neovim evaluates it already when it peeks at the next key while inserting the key typed
          -- before Enter (keys typed fast, a busy editor): "body<CR>" answered "bod". A plain mapping runs only when
          -- Enter itself is handled, after every key before it is in the prompt.
          i_cr = {
            "<cr>",
            function(self)
              if vim.fn.pumvisible() == 1 then
                vim.api.nvim_feedkeys(vim.keycode("<C-y>"), "n", false) -- accept the completion item
              else
                self:execute("confirm")
              end
            end,
            mode = { "i", "n" },
            expr = false,
            desc = "Confirm",
          },
        },
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
