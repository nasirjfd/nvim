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
    opts = {
      global_keymaps = false, -- our keys live in ftplugin/http.lua (buffer-local)
      default_env = "dev", -- environment name in http-client.env.json
      lsp = { enable = true },
      ui = { display_mode = "split", split_direction = "vertical" },
    },
  },
}
