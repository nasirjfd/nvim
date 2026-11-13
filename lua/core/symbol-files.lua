-- Workspace symbols come from the LSP, which does not honor picker file-visibility toggles.
-- Intersect its results with the same fd/rg listing used by Find Files, including local .ignore rules.
local M = {}
local cache = {}
local FRESH_MS = 3000

-- Test seam: picker tests supply workspace servers without replacing Neovim's global LSP registry.
function M.clients()
  return vim.lsp.get_clients()
end

local function absolute(file, cwd)
  return vim.fs.normalize(file:sub(1, 1) == "/" and file or cwd .. "/" .. file)
end

local function within(path, root)
  path, root = vim.fs.normalize(path), vim.fs.normalize(root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

-- Workspace symbols are not document-local: a blank, HTTP or Explorer buffer need not be attached
-- to the language server. Use already-running servers for this workspace, not unrelated projects.
local function symbols(opts, ctx, cwd)
  local lsp = require("snacks.picker.source.lsp")
  local clients = {}
  for _, client in ipairs(M.clients()) do
    local relevant = false
    local roots = {}
    if client.root_dir then
      roots[#roots + 1] = client.root_dir
    end
    for _, folder in ipairs(client.workspace_folders or {}) do
      roots[#roots + 1] = vim.uri_to_fname(folder.uri)
    end
    for _, root in ipairs(roots) do
      if within(cwd, root) or within(root, cwd) then
        relevant = true
        break
      end
    end
    if relevant and client:supports_method("workspace/symbol") then
      clients[#clients + 1] = client
    end
  end
  if #clients == 0 then
    if #lsp.get_clients(ctx.filter.current_buf, "workspace/symbol") == 0
      and not ctx.picker._symbol_server_hint then
      ctx.picker._symbol_server_hint = true
      vim.schedule(function()
        if not ctx.picker.closed then
          vim.notify("No workspace-symbol server is running here. Open a source file to start its language server.",
            vim.log.levels.INFO, { title = "Workspace Symbols" })
        end
      end)
    end
    -- Preserve Snacks' normal attached-buffer handling (and its delayed LspAttach support).
    return lsp.symbols(opts, ctx)
  end
  local buf = ctx.filter.current_buf
  local filter = opts.filter[vim.bo[buf].filetype]
  filter = filter == nil and opts.filter.default or filter
  local query = ctx.filter.search
  return function(cb)
    for _, client in ipairs(clients) do
      lsp.request(client, "workspace/symbol", function()
        return { query = query }
      end, function(server, results)
        local items = lsp.results_to_items(server, results, {
          text_with_file = true,
          filter = function(symbol)
            return type(filter) == "boolean" or vim.tbl_contains(filter, lsp.symbol_kind(symbol.kind))
          end,
        })
        for _, item in ipairs(items) do
          cb(item)
        end
      end)
    end
  end
end

function M.finder(opts, ctx)
  local cwd = ctx:cwd()
  local key = table.concat({ cwd, tostring(opts.ignored), tostring(opts.hidden), vim.inspect(opts.exclude) }, "\0")
  local find_symbols = symbols(opts, ctx, cwd)
  local file_ctx = ctx:clone()
  -- Symbol query text must not become a filename glob during visibility discovery.
  file_ctx.filter = setmetatable({ search = "", pattern = "" }, { __index = ctx.filter })
  local file_opts = {
    cwd = cwd,
    hidden = opts.hidden,
    ignored = opts.ignored,
    exclude = opts.exclude,
    debug = {},
  }
  return function(cb)
    local entry = cache[key]
    if not entry or vim.uv.now() - entry.time > FRESH_MS then
      local allowed = {}
      local files = require("snacks.picker.source.files").files(file_opts, file_ctx)
      local function add(item)
        if item.file then
          allowed[absolute(item.file, item.cwd or cwd)] = true
        end
      end
      if type(files) == "function" then
        files(add)
      else
        for _, item in ipairs(files) do
          add(item)
        end
      end
      entry = { files = allowed, time = vim.uv.now() }
      if vim.tbl_count(cache) >= 4 then
        cache = {}
      end
      cache[key] = entry
    end
    local function emit(item)
      if item.file and entry.files[absolute(item.file, item.cwd or cwd)] then
        cb(item)
      end
    end
    if type(find_symbols) == "function" then
      find_symbols(emit)
    else
      for _, item in ipairs(find_symbols) do
        emit(item)
      end
    end
  end
end

return M
