-- Kulala: HTTP client for .http / .rest files (replaces Bruno in the terminal).
-- Its LSP (completion, hover, symbols, formatting, diagnostics) runs in-process (opts.lsp.enable),
-- so there is nothing to install via Mason or list in lsp/.
return {
  {
    "mistweaverco/kulala.nvim",
    -- v6+ moved the backend (kulala-core) to a closed-source binary that needs a license token.
    -- v5.3.4 is the last curl-based, token-free release; drop the pin if you get a token.
    commit = "6656c9d332735ca6a27725e0fb45a1715c4372d9", -- tag v5.3.4
    ft = { "http", "rest" },
    init = function()
      -- Show the whole response in the result window instead of collapsed (indent) folds
      vim.api.nvim_create_autocmd("BufWinEnter", {
        group = vim.api.nvim_create_augroup("KulalaNoFold", { clear = true }),
        callback = function(args)
          if vim.api.nvim_buf_get_name(args.buf):match("^kulala://ui") then
            for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
              vim.wo[win].foldenable = false
            end
          end
        end,
      })
    end,
    opts = {
      global_keymaps = false, -- our keys live in ftplugin/http.lua (buffer-local)
      -- Keys of the response window, added to Kulala's own: q and Esc hide it (closing the window
      -- before its buffer, see core/kulala-ui.lua)
      kulala_keymaps = {
        ["Close"] = {
          "q",
          function()
            require("core.kulala-ui").hide_response()
          end,
          prefix = false,
        },
        -- F filters the response: jq for JSON (Kulala's own), a CSS selector for HTML
        ["Show filter"] = {
          "F",
          function()
            require("core.kulala-ui").filter()
          end,
        },
        ["Close (Esc)"] = {
          "<Esc>",
          function()
            require("core.kulala-ui").hide_response()
          end,
          prefix = false,
        },
      },
      default_env = "dev", -- environment name in http-client.env.json
      lsp = { enable = true },
      ui = {
        display_mode = "split",
        split_direction = "vertical", -- response to the right of the request
        -- client.log() in a script is shown in the result's Script Output tab. In a terminal Kulala
        -- also `print`s it, and a long value (response.json) filled the screen with a -- More --
        -- prompt that had to be dismissed after every request.
        disable_script_print_output = true,
        -- Show responses up to 5 MB (Kulala's default of 32 KB replaced a 63 KB JSON response
        -- with a "size of response is > 32Kb" note)
        max_response_size = 5 * 1024 * 1024,
        -- Long lines of the response wrap at word boundaries, continuing at the line's indent
        win_opts = {
          wo = { wrap = true, linebreak = true, breakindent = true, breakindentopt = "shift:2" },
        },
      },
    },
  },
}
