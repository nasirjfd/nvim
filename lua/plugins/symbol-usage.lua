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
    -- Same as the default format, but "impls" only appears when there are some
    text_format = function(symbol)
      local fragments = {}
      if symbol.references then
        local usage = symbol.references == 1 and "usage" or "usages"
        table.insert(fragments, ("%s %s"):format(symbol.references == 0 and "no" or symbol.references, usage))
      end
      if symbol.implementation and symbol.implementation > 0 then
        local impl = symbol.implementation == 1 and "implementation" or "implementations"
        table.insert(fragments, ("%s %s"):format(symbol.implementation, impl))
      end
      local stacked = symbol.stacked_count > 0 and (" | +%s"):format(symbol.stacked_count) or ""
      return table.concat(fragments, ", ") .. stacked
    end,
    -- Intelephense lists a method as an implementation of itself, so every method showed
    -- "1 impls". Drop the location the request was made from.
    symbol_filter = function(ctx)
      if ctx.method ~= "textDocument/implementation" then
        return function()
          return true
        end
      end
      local line = ctx.params.position.line
      return function(location)
        local range = location.targetSelectionRange or location.range
        local uri = location.targetUri or location.uri
        return not (uri == ctx.params.textDocument.uri and range.start.line == line)
      end
    end,
  },
}
