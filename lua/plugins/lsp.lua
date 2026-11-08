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

-- the running glide of a symbol jump, as a function that ends it at once
local member_glide

-- Where the members are. Asking the language server blocks until it answers (a full second while it
-- is still starting), so a jump never waits for it: the answer is cached per buffer version, fetched
-- in the background, and until it is there treesitter finds the members (PHP) at once.
local member_cache = {} -- bufnr -> { tick = changedtick, lines = {...} }
local member_pending = {} -- bufnr -> changedtick of a request in flight

local function members_from_symbols(results)
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
        table.insert(lines, { line = name.start.line, col = name.start.character, utf16 = true })
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

local TS_MEMBERS = {
  class_declaration = false,
  trait_declaration = false,
  method_declaration = true,
  function_definition = true,
}

local function members_from_treesitter(bufnr)
  if vim.bo[bufnr].filetype ~= "php" then
    return nil
  end
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end
  local lines = {}
  local function walk(node, inside_callable)
    local type = node:type()
    local callable = TS_MEMBERS[type]
    if callable ~= nil and not inside_callable then
      local name = node:field("name")[1]
      if name then
        local row, col = name:start()
        table.insert(lines, { line = row, col = col })
      end
    end
    for child in node:iter_children() do
      if child:named() then
        walk(child, inside_callable or callable == true)
      end
    end
  end
  for _, tree in ipairs(parser:parse()) do
    walk(tree:root(), false)
  end
  table.sort(lines, function(a, b)
    return a.line < b.line
  end)
  return lines
end

--- Members of the buffer for a jump, without waiting. `on_late(lines)` runs if there is nothing to
--- go on yet (no treesitter, no cached answer) and the language server answers later.
local function collect_member_lines(bufnr, on_late)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cached = member_cache[bufnr]
  if cached and cached.tick == tick then
    return cached.lines
  end
  if member_pending[bufnr] ~= tick and #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/documentSymbol" }) > 0 then
    member_pending[bufnr] = tick
    local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
    vim.lsp.buf_request_all(bufnr, "textDocument/documentSymbol", params, function(results)
      member_pending[bufnr] = nil
      if vim.api.nvim_buf_is_valid(bufnr) then
        local lines = members_from_symbols(results or {})
        if #lines > 0 then
          member_cache[bufnr] = { tick = tick, lines = lines }
        end
        if on_late then
          on_late(lines)
        end
      end
    end)
  end
  local from_syntax = members_from_treesitter(bufnr)
  if from_syntax and #from_syntax > 0 then
    return from_syntax
  end
  return cached and cached.lines or nil
end

local goto_member
function goto_member(bufnr, direction, late)
  -- A glide still running holds the cursor on a line it passes: end it first, so the next jump
  -- starts from where the previous one was going
  if member_glide then
    member_glide()
  end
  local waiting = false
  local lines = collect_member_lines(bufnr, function()
    if waiting and not late and vim.api.nvim_get_current_buf() == bufnr then
      goto_member(bufnr, direction, true)
    end
  end)
  if not lines then
    waiting = true -- the language server will answer and the jump is made then
    return
  end
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
  else
    for i = #lines, 1, -1 do
      if lines[i].line < cur then
        target = lines[i]
        break
      end
    end
  end

  if not target then
    return -- already at the first/last symbol: stay there instead of wrapping around
  end

  -- LSP columns are UTF-16 offsets; put the cursor on the first character of the symbol's name
  local text = vim.api.nvim_buf_get_lines(bufnr, target.line, target.line + 1, false)[1] or ""
  local ok, col = true, target.col
  if target.utf16 then
    ok, col = pcall(vim.str_byteindex, text, "utf-16", target.col)
  end
  -- A target that is already on screen is not scrolled to. One that is off screen is put in the
  -- middle (Neovim's minimal scroll would leave it on the window's edge, with its usage line cut
  -- off) with a short glide of about 100 ms that ends exactly there. snacks.nvim's own smooth scroll
  -- wobbles around the target for ~100 ms, so it is skipped for this jump.
  local win = vim.api.nvim_get_current_win()
  local visible = target.line + 1 >= vim.fn.line("w0") and target.line + 1 <= vim.fn.line("w$")
  if visible then
    vim.api.nvim_win_set_cursor(0, { target.line + 1, ok and col or 0 })
    return
  end
  local start = vim.fn.winsaveview()
  vim.b[bufnr].snacks_scroll = false
  vim.api.nvim_win_set_cursor(0, { target.line + 1, ok and col or 0 })
  vim.cmd("normal! zz")
  local final = vim.fn.winsaveview()
  vim.fn.winrestview(start)
  local height = vim.api.nvim_win_get_height(win)
  local frames, frame = 10, 0
  local timer = vim.uv.new_timer()
  member_glide = function()
    member_glide = nil
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_call(win, function()
          vim.fn.winrestview(final)
        end)
      end
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.b[bufnr].snacks_scroll = nil
        end
      end, 100)
    end
  end
  timer:start(
    10,
    10,
    vim.schedule_wrap(function()
      if not member_glide then
        return
      end
      frame = frame + 1
      if frame >= frames then
        return member_glide()
      end
      local t = 1 - (1 - frame / frames) ^ 3 -- outCubic
      local top = math.floor(start.topline + (final.topline - start.topline) * t + 0.5)
      local line = math.min(math.max(final.lnum, top), top + height - 1)
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview({ topline = top, lnum = line, col = final.col, topfill = 0 })
      end)
    end)
  )
end

-- The jump keys work from the moment a PHP file opens (treesitter finds the members), not only after
-- the language server has attached: before that, S is "substitute line" (it enters insert mode and
-- loads the completion plugins, a long stall) and U is "undo line".
vim.api.nvim_create_autocmd("FileType", {
  pattern = "php",
  callback = function(args)
    for lhs, direction in pairs({ ["[m"] = -1, ["]m"] = 1, U = -1, S = 1 }) do
      vim.keymap.set("n", lhs, function()
        goto_member(args.buf, direction)
      end, { buffer = args.buf, silent = true, desc = "Prev/Next Class/Method" })
    end
  end,
})

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
        callback = function()
          -- not while selecting: the selection highlight owns that (it flashed with both)
          if vim.fn.mode():match("^[vV\22sS\19]") then
            return
          end
          vim.lsp.buf.document_highlight()
        end,
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
