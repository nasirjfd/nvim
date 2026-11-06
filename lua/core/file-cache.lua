-- Find Files (<leader><space>) opens at once from a cache of the project's file list, like the
-- JetBrains "Search Everywhere": the list is kept as one string per project folder (about 5 MB for
-- 60k files), shown immediately on open, and refreshed in the background; if the refresh found
-- changes the open picker is updated in place. Entries not used for IDLE_MINUTES are dropped and at
-- most MAX_ENTRIES folders are kept.
local M = {}

local MAX_ENTRIES = 2
local IDLE_MINUTES = 15
local FRESH_MS = 3000 -- a list newer than this is not re-scanned on open

local cache = {} ---@type table<string, {raw: string, scanned: number, used: number, running: boolean}>
local ignored_parent = {} ---@type table<string, boolean> cwd -> is ignored by its parent repo

local function now()
  return vim.uv.now()
end

--- Options of the file picker for the current folder (what <leader><space> passes to the picker).
function M.opts()
  local cwd = vim.fn.getcwd()
  -- A cwd ignored by its parent repo (e.g. vendor/) would list nothing, so skip the parent's ignore
  -- files there; its own .gitignore files still apply. Looked up once per folder, not per open.
  if ignored_parent[cwd] == nil then
    ignored_parent[cwd] = vim.system({ "git", "check-ignore", "-q", "." }, { cwd = cwd }):wait().code == 0
  end
  return {
    cwd = cwd,
    -- Ignored files stay hidden until <a-i> in the picker or <leader>uI
    ignored = vim.g.show_ignored == true,
    hidden = vim.g.show_ignored or false,
    args = ignored_parent[cwd] and { "--no-ignore-parent" } or nil,
    finder = M.finder,
  }
end

local function key_of(opts)
  return table.concat({ opts.cwd, tostring(opts.ignored), tostring(opts.hidden), table.concat(opts.args or {}, " ") }, "\0")
end

local function command(opts)
  if vim.fn.executable("fd") ~= 1 then
    return nil
  end
  local args = { "fd", "--type", "f", "--type", "l", "--color", "never", "-E", ".git" }
  if opts.hidden then
    args[#args + 1] = "--hidden"
  end
  if opts.ignored then
    args[#args + 1] = "--no-ignore"
  end
  vim.list_extend(args, opts.args or {})
  return args
end

local function evict()
  local keys = vim.tbl_keys(cache)
  table.sort(keys, function(a, b)
    return cache[a].used > cache[b].used
  end)
  for i, key in ipairs(keys) do
    if i > MAX_ENTRIES or now() - cache[key].used > IDLE_MINUTES * 60 * 1000 then
      cache[key] = nil
    end
  end
end

--- Scan in the background; `on_change` runs when the list differs from the cached one.
local function refresh(opts, on_change)
  local cmd = command(opts)
  local key = key_of(opts)
  local entry = cache[key]
  if not cmd or (entry and entry.running) then
    return
  end
  if entry then
    entry.running = true
  end
  vim.system(cmd, { cwd = opts.cwd, text = true }, function(result)
    vim.schedule(function()
      local current = cache[key]
      if current then
        current.running = false
      end
      if result.code ~= 0 or not result.stdout then
        return
      end
      local changed = not current or current.raw ~= result.stdout
      cache[key] = { raw = result.stdout, scanned = now(), used = current and current.used or now(), running = false }
      evict()
      if changed and current and on_change then
        on_change()
      end
    end)
  end)
end

--- Prepare the cache for the current folder without opening a picker.
function M.warm()
  local opts = M.opts()
  if not cache[key_of(opts)] then
    refresh(opts)
  end
end

---@type snacks.picker.finder
function M.finder(opts, ctx)
  local original = require("snacks.picker.source.files").files
  -- Anything but a plain listing of the folder goes through snacks' own finder
  if opts.live or opts.ft or opts.dirs or opts.rtp or opts.follow or opts.exclude and #opts.exclude > 0 or ctx.filter.search ~= "" then
    return original(opts, ctx)
  end
  local key = key_of(opts)
  local entry = cache[key]
  if not entry then
    refresh(opts) -- fills the cache for the next time
    return original(opts, ctx)
  end

  entry.used = now()
  if now() - entry.scanned > FRESH_MS then
    local picker = ctx.picker
    refresh(opts, function()
      if picker and not picker.closed then
        picker:find()
      end
    end)
  end
  local items, cwd = {}, opts.cwd
  for line in entry.raw:gmatch("[^\n]+") do
    items[#items + 1] = { text = line, file = line, cwd = cwd }
  end
  return items
end

function M.setup()
  local group = vim.api.nvim_create_augroup("FileCache", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
    group = group,
    callback = function()
      vim.defer_fn(M.warm, 1500)
    end,
  })
  -- Drop what has not been used for a while, even when no picker is opened
  local timer = vim.uv.new_timer()
  timer:start(5 * 60 * 1000, 5 * 60 * 1000, vim.schedule_wrap(evict))
end

return M
