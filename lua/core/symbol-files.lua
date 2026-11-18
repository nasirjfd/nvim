-- Workspace symbols come from the LSP, which does not honor picker file-visibility toggles.
-- Intersect its results with the same fd/rg listing used by Find Files, including local .ignore rules.
local Async = require("snacks.picker.util.async")
local M = {}
local cache = {}
local FRESH_MS = 60000
-- Server answers per workspace + query: reopening the picker shows them at once instead of
-- waiting for the language server again. Dropped on any save / external change (M.invalidate).
local answers = {}
local ANSWER_MS = 60000

-- Entries are never thrown away on a change: they are marked stale (epoch) and still shown at once,
-- while a fresh copy is fetched behind them (stale-while-revalidate).
local epoch = 0

function M.invalidate()
  epoch = epoch + 1
end

vim.api.nvim_create_autocmd({ "BufWritePost", "FileChangedShellPost" }, {
  group = vim.api.nvim_create_augroup("symbol_files_cache", { clear = true }),
  callback = M.invalidate,
})

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
  local akey = table.concat({ cwd, query, vim.inspect(filter), #clients }, "\0")
  return function(cb)
    local hit = answers[akey]
    local fresh = hit and hit.epoch == epoch and vim.uv.now() - hit.time <= ANSWER_MS
    if hit then
      for _, item in ipairs(hit.items) do
        cb(vim.deepcopy(item))
      end
      if fresh then
        return
      end
    end
    local collected, pending, my_epoch = {}, #clients, epoch
    local function emit_item(item)
      if not hit then
        cb(item)
      end
    end
    local function fetch()
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
          collected[#collected + 1] = vim.deepcopy(item)
          emit_item(item)
        end
        pending = pending - 1
        if pending == 0 then
          if vim.tbl_count(answers) >= 50 then
            answers = {}
          end
          local changed = hit and #hit.items ~= #collected
          answers[akey] = { items = collected, time = vim.uv.now(), epoch = my_epoch }
          if changed and not ctx.picker.closed then
            vim.schedule(function()
              if not ctx.picker.closed then
                ctx.picker:find()
              end
            end)
          end
        end
      end)
    end
    end
    if not hit then
      return fetch()
    end
    -- Stale answer already shown: refresh only if the user paused on this query (typing makes a
    -- new query per key; asking the server for every prefix would only load it).
    vim.defer_fn(function()
      local picker = ctx.picker
      if not picker.closed and picker:filter().search == query then
        fetch()
      end
    end, 250)
  end
end

-- Byte columns (1-based) of the typed text in a symbol name: the whole text when it occurs, else the
-- letters in order (the server answers fuzzy), preferring the earliest start.
function M.positions(name, query)
  query = query:gsub("%s+", ""):lower()
  if query == "" then
    return {}
  end
  local lower = name:lower()
  local from, to = lower:find(query, 1, true)
  local out = {}
  if from then
    for i = from, to do
      out[#out + 1] = i
    end
    return out
  end
  -- Fuzzy: take the longest chunk of the query that occurs next, so matches stay contiguous.
  local qi, pos = 1, 1
  while qi <= #query do
    local found
    for len = #query - qi + 1, 1, -1 do
      local f = lower:find(query:sub(qi, qi + len - 1), pos, true)
      if f then
        for k = 0, len - 1 do
          out[#out + 1] = f + k
        end
        pos, qi, found = f + len, qi + len, true
        break
      end
    end
    if not found then
      return {}
    end
  end
  return out
end

-- Snacks does not mark the typed text in symbol names (live search has no matcher positions).
function M.format(item, picker)
  local ret = Snacks.picker.format.lsp_symbol(item, picker)
  local kind = item.lsp_kind or item.kind or "Unknown"
  kind = picker.opts.icons.kinds[kind] and kind or "Unknown"
  local name = vim.trim((item.name or ""):gsub("\r?\n", " "))
  if name ~= "" then
    local offset = #picker.opts.icons.kinds[kind] + 1
    -- Entries sit right before the name's text, like Snacks' own syntax highlight of it.
    local at
    for i, seg in ipairs(ret) do
      if seg[1] == name and not seg.virtual then
        at = i
        break
      end
    end
    if at then
      local marks = Snacks.picker.highlight.matches({}, M.positions(name, picker:filter().search or ""), offset)
      for _, mark in ipairs(marks) do
        mark.priority = 300 -- above the name's own syntax highlight (100)
      end
      for i = #marks, 1, -1 do
        table.insert(ret, at, marks[i])
      end
    end
  end
  return ret
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
    local stale = entry and (entry.epoch ~= epoch or vim.uv.now() - entry.time > FRESH_MS)
    local scan = function()
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
      if vim.tbl_count(cache) >= 4 and not cache[key] then
        cache = {}
      end
      entry = { files = allowed, time = vim.uv.now(), epoch = epoch }
      cache[key] = entry
    end
    if not entry then
      scan()
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
    if stale and not entry.rescanning then
      -- The shown results used the old file list; rescan in the background for the next search.
      entry.rescanning = true
      Async.new(function()
        Async.yield()
        scan()
      end)
    end
  end
end

return M
