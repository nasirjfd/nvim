-- ════════════════════════════════════════════════════════════════════════════
-- Goto Next/Prev Class/Method (LSP document symbols)
-- Mirrors VSCode's mishkinf.goto-next-previous-member (shift+u / shift+s),
-- also on ]m / [m. In normal mode "S" is taken from Flash's treesitter jump (still on x/o).
-- ════════════════════════════════════════════════════════════════════════════
local MEMBER_KINDS = {
  [vim.lsp.protocol.SymbolKind.Class] = true,
  [vim.lsp.protocol.SymbolKind.Method] = true,
  [vim.lsp.protocol.SymbolKind.Constructor] = true,
  [vim.lsp.protocol.SymbolKind.Function] = true,
}

local function collect_member_lines(bufnr)
  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
  local ok, results = pcall(vim.lsp.buf_request_sync, bufnr, "textDocument/documentSymbol", params, 1000)
  if not ok or not results then
    return {}
  end

  local lines = {}
  -- Closures, callbacks and functions declared inside another function are not members
  local CALLABLE = {
    [vim.lsp.protocol.SymbolKind.Method] = true,
    [vim.lsp.protocol.SymbolKind.Constructor] = true,
    [vim.lsp.protocol.SymbolKind.Function] = true,
  }
  local function anonymous(name)
    return name == "" or name:find("^[<(]") ~= nil or name:find("callback$") ~= nil
  end

  local function collect(symbols, inside_callable)
    for _, sym in ipairs(symbols or {}) do
      local range = sym.range or (sym.location and sym.location.range)
      if range and MEMBER_KINDS[sym.kind] and not inside_callable and not anonymous(sym.name or "") then
        -- selectionRange points at the symbol's name (e.g. the method name, not `public function`)
        local name = sym.selectionRange or range
        table.insert(lines, { line = name.start.line, col = name.start.character })
      end
      if sym.children then
        collect(sym.children, inside_callable or CALLABLE[sym.kind] == true)
      end
    end
  end

  for _, res in pairs(results) do
    if res.result then
      collect(res.result)
    end
  end

  table.sort(lines, function(a, b)
    return a.line < b.line
  end)
  return lines
end

local function goto_member(bufnr, direction)
  local lines = collect_member_lines(bufnr)
  if #lines == 0 then
    vim.notify("No class/method/function symbols found", vim.log.levels.WARN)
    return
  end

  local cur = vim.api.nvim_win_get_cursor(0)[1] - 1
  local target
  if direction > 0 then
    for _, pos in ipairs(lines) do
      if pos.line > cur then
        target = pos
        break
      end
    end
    target = target or lines[1]
  else
    for i = #lines, 1, -1 do
      if lines[i].line < cur then
        target = lines[i]
        break
      end
    end
    target = target or lines[#lines]
  end

  -- LSP columns are UTF-16 offsets; put the cursor on the first character of the symbol's name
  local text = vim.api.nvim_buf_get_lines(bufnr, target.line, target.line + 1, false)[1] or ""
  local ok, col = pcall(vim.str_byteindex, text, "utf-16", target.col)
  vim.api.nvim_win_set_cursor(0, { target.line + 1, ok and col or 0 })
end

-- ════════════════════════════════════════════════════════════════════════════
-- LSP Keymaps (applied per-buffer on attach)
-- ════════════════════════════════════════════════════════════════════════════
local function setup_keymaps(bufnr)
  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
  end

  -- Hover & Signature
  map("n", "K", function()
    vim.lsp.buf.hover({ border = "rounded", max_height = 25, max_width = 120 })
  end, "Hover")
  map({ "n", "i" }, "<C-k>", vim.lsp.buf.signature_help, "Signature Help")

  -- gd, gD, gr, gi, gy handled by Snacks picker (snacks.lua)

  -- Diagnostics navigation
  map("n", "[d", function()
    vim.diagnostic.jump({ count = -1 })
  end, "Prev Diagnostic")
  map("n", "]d", function()
    vim.diagnostic.jump({ count = 1 })
  end, "Next Diagnostic")

  -- Goto next/prev class/method/function
  map("n", "[m", function()
    goto_member(bufnr, -1)
  end, "Prev Class/Method")
  map("n", "]m", function()
    goto_member(bufnr, 1)
  end, "Next Class/Method")
  map("n", "U", function()
    goto_member(bufnr, -1)
  end, "Prev Class/Method")
  map("n", "S", function()
    goto_member(bufnr, 1)
  end, "Next Class/Method")

  -- <leader>c = Code
  map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "Code Action")
  map("n", "<leader>cr", vim.lsp.buf.rename, "Rename Symbol")
  map("n", "<leader>cd", vim.diagnostic.open_float, "Line Diagnostic")
  map("n", "<leader>cv", "<cmd>vsplit | lua vim.lsp.buf.definition()<cr>", "Definition in Vsplit")

  -- <leader>l = LSP
  map("n", "<leader>li", "<cmd>checkhealth vim.lsp<cr>", "LSP Info")
  map("n", "<leader>lr", function()
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    local names = {}
    for _, client in ipairs(clients) do
      names[client.name] = true
    end

    for name in pairs(names) do
      vim.lsp.enable(name, false)
      vim.defer_fn(function()
        vim.lsp.enable(name, true)
      end, 100)
    end
  end, "Restart LSP")
  map("n", "<leader>lu", function()
    require("symbol-usage").toggle()
  end, "Toggle Usages Lens")
  map("n", "<leader>lh", function()
    vim.lsp.inlay_hint.enable(
      not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }),
      { bufnr = bufnr }
    )
  end, "Toggle Inlay Hints")
end

-- ════════════════════════════════════════════════════════════════════════════
-- LspAttach Handler
-- ════════════════════════════════════════════════════════════════════════════
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
  callback = function(args)
    local bufnr = args.buf
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client then
      return
    end

    setup_keymaps(bufnr)

    -- Inlay hints and code lens (reference/implementation counts) on by default
    if client:supports_method("textDocument/inlayHint") then
      vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
    end
    if client:supports_method("textDocument/codeLens") then
      vim.lsp.codelens.enable(true, { bufnr = bufnr })
    end

    -- Document highlight on cursor hold
    if client.server_capabilities.documentHighlightProvider then
      local group = vim.api.nvim_create_augroup("LspDocumentHighlight_" .. bufnr, { clear = true })
      vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
        buffer = bufnr,
        group = group,
        callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        buffer = bufnr,
        group = group,
        callback = vim.lsp.buf.clear_references,
      })
    end
  end,
})

-- ════════════════════════════════════════════════════════════════════════════
-- Diagnostic Configuration
-- ════════════════════════════════════════════════════════════════════════════
vim.diagnostic.config({
  virtual_text = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = { border = "rounded", source = true, header = "", prefix = "" },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "󰅚 ",
      [vim.diagnostic.severity.WARN] = "󰀪 ",
      [vim.diagnostic.severity.INFO] = "󰋽 ",
      [vim.diagnostic.severity.HINT] = "󰌶 ",
    },
    numhl = {
      [vim.diagnostic.severity.ERROR] = "ErrorMsg",
      [vim.diagnostic.severity.WARN] = "WarningMsg",
    },
  },
})

-- ════════════════════════════════════════════════════════════════════════════
-- LSP Server Configuration (native Neovim API)
-- Server configs loaded from lsp/ directory, activated with vim.lsp.enable()
-- ════════════════════════════════════════════════════════════════════════════
vim.lsp.config("*", {
  root_markers = { ".git" },
})

vim.lsp.enable({
  "lua_ls",
  "gopls",
  "zls",
  "ts_ls",
  "rust_analyzer",
  "intelephense",
  "bashls",
  "pyright",
  "cssls",
  "html",
  "jsonls",
  "yamlls",
  "sourcekit",
  "laravel_lsp",
})

-- ════════════════════════════════════════════════════════════════════════════
-- Mason: auto-install LSP servers, formatters, and linters
-- ════════════════════════════════════════════════════════════════════════════
return {
  {
    "mason-org/mason.nvim",
    lazy = false,
    opts = {},
  },
  {
    "mason-org/mason-lspconfig.nvim",
    lazy = false,
    dependencies = { "mason-org/mason.nvim" },
    opts = {
      automatic_enable = false,
    },
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    lazy = false,
    dependencies = { "mason-org/mason.nvim" },
    opts = {
      ensure_installed = {
        -- LSP servers
        "lua-language-server",
        "gopls",
        "zls",
        "typescript-language-server",
        "rust-analyzer",
        "intelephense",
        "bash-language-server",
        "pyright",
        "css-lsp",
        "html-lsp",
        "json-lsp",
        "yaml-language-server",
        -- Linters
        "eslint_d",
        { "luacheck", condition = function()
          return vim.fn.executable("luarocks") == 1
        end },
        "golangci-lint",
        "shellcheck",
        "markdownlint",
        "yamllint",
        "jsonlint",
        "htmlhint",
        "stylelint",
        "phpstan",
        "ruff",
        "mypy",
        "sqlfluff",
        -- Formatters
        "stylua",
        "goimports",
        "prettier",
        "black",
        "isort",
        "shfmt",
        "pint",
      },
      -- Avoid restarting the full install queue on every Neovim launch.
      debounce_hours = 24,
    },
  },
}
