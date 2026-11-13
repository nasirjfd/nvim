-- Workspace symbols come from the LSP, which does not honor picker file-visibility toggles.
-- Intersect its results with the same fd/rg listing used by Find Files, including local .ignore rules.
local M = {}
local cache = {}
local FRESH_MS = 3000

local function absolute(file, cwd)
  return vim.fs.normalize(file:sub(1, 1) == "/" and file or cwd .. "/" .. file)
end

function M.finder(opts, ctx)
  local cwd = ctx:cwd()
  local key = table.concat({ cwd, tostring(opts.ignored), tostring(opts.hidden), vim.inspect(opts.exclude) }, "\0")
  local symbols = require("snacks.picker.source.lsp").symbols(opts, ctx)
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
    if type(symbols) == "function" then
      symbols(emit)
    else
      for _, item in ipairs(symbols) do
        emit(item)
      end
    end
  end
end

return M
