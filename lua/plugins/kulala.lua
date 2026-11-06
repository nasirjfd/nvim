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
    keys = {
      { "<leader>Rb", function() require("kulala").scratchpad() end, desc = "Kulala: Open scratchpad" },
      { "<leader>Re", function() require("kulala").set_selected_env() end, desc = "Kulala: Select environment" },
    },
    opts = {
      global_keymaps = true, -- <leader>R… inside http/rest buffers (see lua/kulala/config/keymaps.lua)
      global_keymaps_prefix = "<leader>R",
      default_env = "dev", -- environment name in http-client.env.json
      lsp = { enable = true },
      ui = { display_mode = "split", split_direction = "vertical" },
    },
  },
}
