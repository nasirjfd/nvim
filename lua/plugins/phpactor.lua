return {
  "gbprod/phpactor.nvim",
  ft = "php",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    lspconfig = {
      enabled = true, -- keep it running (warm), just muzzle it below
      options = {
        handlers = {
          ["textDocument/publishDiagnostics"] = function() end, -- silence phpactor diagnostics
        },
        on_attach = function(client, _)
          -- strip capabilities so cmp/nvim never routes completion/hover/def to phpactor
          client.server_capabilities.completionProvider = nil
          client.server_capabilities.hoverProvider = nil
          client.server_capabilities.definitionProvider = nil
          client.server_capabilities.documentHighlightProvider = nil
          -- codeActionProvider / executeCommand stay intact → generate method still works
        end,
      },
    },
  },
  keys = {
    {
      "<leader>lm",
      function()
        require("phpactor").rpc("context_menu", {})
      end,
      desc = "Phpactor: generate method (context menu)",
      ft = "php",
    },
  },
}
