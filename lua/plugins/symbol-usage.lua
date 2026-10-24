-- Usage/implementation counts above classes, interfaces, functions and methods.
-- Language servers like Intelephense send no code lens, so this plugin asks for
-- references/implementations itself. Toggle with <leader>lu.
return {
  "Wansmer/symbol-usage.nvim",
  event = "LspAttach",
  opts = {
    vt_position = "above",
    kinds = {
      vim.lsp.protocol.SymbolKind.Class,
      vim.lsp.protocol.SymbolKind.Interface,
      vim.lsp.protocol.SymbolKind.Enum,
      vim.lsp.protocol.SymbolKind.Function,
      vim.lsp.protocol.SymbolKind.Method,
    },
    -- Intelephense resolves references from the start of the name
    symbol_request_pos = "start",
    references = { enabled = true, include_declaration = false },
    definition = { enabled = false },
    implementation = { enabled = true },
    -- Hide "0 implementations" noise and the pending placeholder
    request_pending_text = false,
  },
}
