-- Usage/implementation counts above classes, interfaces, functions and methods.
-- Language servers like Intelephense send no code lens, so this plugin asks for
-- references/implementations itself. Toggle with <leader>lu.
-- No lens in a diff view: it is noise there, and a line above a method exists in one pane only.
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

local function refresh_diff_buffers()
  vim.schedule(function()
    local buf = require("symbol-usage.buf")
    local state = require("symbol-usage.state")
    for bufnr in pairs(state.buffers or {}) do
      if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) and #vim.fn.win_findbuf(bufnr) > 0 then
        buf.clear_buffer(bufnr)
        if not in_diff(bufnr) then
          buf.attach_buffer(bufnr)
        end
      end
    end
  end)
end

-- Room for the lens is reserved the moment a file opens, from treesitter, before the language
-- server has answered: a blank line above every class/function/method. When symbol-usage draws
-- its own line for a symbol, it takes over the reserved one in the same tick, so the lens appears
-- without anything below it moving. Reserved lines nothing took over are dropped later.
local reserve_ns = vim.api.nvim_create_namespace("lens_reserve")
local reserve_filetypes = { php = true }
local reserve_nodes = {
  class_declaration = true,
  interface_declaration = true,
  trait_declaration = true,
  enum_declaration = true,
  function_definition = true,
  method_declaration = true,
  arrow_function = true,
  anonymous_function = true,
}

local reserve_timers = {}

local function clear_reserve(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, reserve_ns, 0, -1)
  end
end

local function reserve(bufnr)
  if not (vim.api.nvim_buf_is_valid(bufnr) and reserve_filetypes[vim.bo[bufnr].filetype]) then
    return
  end
  if vim.b[bufnr].lens_reserved or vim.bo[bufnr].buftype == "nofile" or in_diff(bufnr) then
    return
  end
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return
  end
  local rows = {}
  local function walk(node)
    if reserve_nodes[node:type()] then
      local name = node:field("name")[1]
      rows[(name or node):start()] = true
    end
    for child in node:iter_children() do
      if child:named() and child:type() ~= "string" then
        walk(child)
      end
    end
  end
  for _, tree in ipairs(parser:parse()) do
    walk(tree:root())
  end
  vim.b[bufnr].lens_reserved = true
  for row in pairs(rows) do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, reserve_ns, row, 0, {
      virt_lines = { { { " ", "NonText" } } },
      virt_lines_above = true,
    })
  end
  -- Whatever the language server never claimed (it may be slow, or absent) is released later
  vim.defer_fn(function()
    clear_reserve(bufnr)
  end, 20000)
end

-- The counts are the comment colour faded towards the background (keep 35% of it)
local function fade()
  local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  if not comment.fg then
    return
  end
  local bg = normal.bg or 0x000000
  local function mix(shift)
    local a, b = bit.band(bit.rshift(comment.fg, shift), 0xff), bit.band(bit.rshift(bg, shift), 0xff)
    return math.floor(a * 0.35 + b * 0.65)
  end
  vim.api.nvim_set_hl(0, "SymbolUsageText", { fg = bit.lshift(mix(16), 16) + bit.lshift(mix(8), 8) + mix(0) })
end

return {
  "Wansmer/symbol-usage.nvim",
  event = "LspAttach",
  config = function(_, opts)
    require("symbol-usage").setup(opts)
    local utils = require("symbol-usage.utils")
    local make = utils.make_extmark_opts
    utils.make_extmark_opts = function(text, o, line, bufnr, id)
      -- the real line takes the reserved one's place within this same tick
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, reserve_ns, { line, 0 }, { line, -1 }, {})) do
        vim.api.nvim_buf_del_extmark(bufnr, reserve_ns, mark[1])
      end
      -- once the lines stop coming, what is left over was not a symbol: release it
      local timer = vim.uv.new_timer()
      reserve_timers[bufnr] = reserve_timers[bufnr] or timer
      if reserve_timers[bufnr] ~= timer then
        timer:close()
        timer = reserve_timers[bufnr]
      end
      timer:stop()
      timer:start(1500, 0, vim.schedule_wrap(function()
        clear_reserve(bufnr)
      end))
      return make(text, o, line, bufnr, id)
    end
    fade()
    vim.api.nvim_create_autocmd("ColorScheme", { callback = fade })
  end,
  init = function()
    vim.api.nvim_create_autocmd({ "FileType", "BufReadPost" }, {
      callback = function(args)
        vim.schedule(function()
          reserve(args.buf)
        end)
      end,
    })
    vim.api.nvim_create_autocmd("User", {
      pattern = { "CodeDiffOpen", "CodeDiffClose", "CodeDiffFileSelect" },
      callback = function()
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if in_diff(bufnr) then
            clear_reserve(bufnr)
          end
        end
        if package.loaded["symbol-usage"] then
          refresh_diff_buffers()
        end
      end,
    })
  end,

  opts = {
    disable = { cond = { in_diff } },
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
    -- "N usage", and "N impl" when there are implementations
    text_format = function(symbol)
      local fragments = {}
      if symbol.references then
        table.insert(fragments, ("%d usage"):format(symbol.references))
      end
      if symbol.implementation and symbol.implementation > 0 then
        table.insert(fragments, ("%d impl"):format(symbol.implementation))
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
