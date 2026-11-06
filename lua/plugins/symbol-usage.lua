-- Usage/implementation counts above classes, interfaces, functions and methods.
-- Language servers like Intelephense send no code lens, so this plugin asks for
-- references/implementations itself. Toggle with <leader>lu.
-- A line above a method exists in one pane only, so in a diff it would push the right pane a row
-- below the left one. Buffers shown in a diff get the count at the end of the line instead.
local function in_diff(bufnr)
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  if not lifecycle then
    return false
  end
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    if lifecycle.get_session(vim.api.nvim_win_get_tabpage(win)) then
      return true
    end
  end
  return false
end

local function patch_position()
  local utils = require("symbol-usage.utils")
  if utils._diff_aware then
    return
  end
  utils._diff_aware = true
  local make = utils.make_extmark_opts
  utils.make_extmark_opts = function(text, opts, line, bufnr, id)
    if opts.vt_position == "above" and in_diff(bufnr) then
      opts = vim.tbl_extend("force", opts, { vt_position = "end_of_line" })
    end
    return make(text, opts, line, bufnr, id)
  end
end

local function refresh_diff_buffers()
  vim.schedule(function()
    local buf = require("symbol-usage.buf")
    local state = require("symbol-usage.state")
    for bufnr in pairs(state.buffers or {}) do
      if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) and #vim.fn.win_findbuf(bufnr) > 0 then
        buf.clear_buffer(bufnr)
        buf.attach_buffer(bufnr)
      end
    end
  end)
end

return {
  "Wansmer/symbol-usage.nvim",
  event = "LspAttach",
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = { "CodeDiffOpen", "CodeDiffClose", "CodeDiffFileSelect" },
      callback = function()
        if package.loaded["symbol-usage"] then
          refresh_diff_buffers()
        end
      end,
    })
  end,
  config = function(_, opts)
    require("symbol-usage").setup(opts)
    patch_position()
  end,
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
    -- The line is reserved as soon as the symbols are known, with a blank placeholder that the
    -- count later replaces in place, so counts arriving never push the text down.
    request_pending_text = { { " ", "SymbolUsageText" } },
    -- Same as the default format, but "impls" only appears when there are some
    text_format = function(symbol)
      local fragments = {}
      if symbol.references then
        table.insert(fragments, symbol.references .. "u")
      end
      if symbol.implementation and symbol.implementation > 0 then
        table.insert(fragments, symbol.implementation .. "i")
      end
      local stacked = symbol.stacked_count > 0 and (" | +%s"):format(symbol.stacked_count) or ""
      return table.concat(fragments, " ") .. stacked
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
