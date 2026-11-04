-- ============================================================================
-- Pick up file changes made outside Neovim (Claude Code, git, formatters) right away.
--
-- One recursive watcher on the working directory (FSEvents on macOS) batches the changes and:
--   * reloads open buffers whose file changed (:checktime), without waiting for a focus change;
--   * notifies language servers that expect the editor to watch files for them. intelephense
--     never registers watchers (its VS Code extension watches **/*.php itself), so without this
--     it keeps reporting e.g. "Undefined function" for code added on disk until Neovim restarts;
--   * re-runs nvim-lint (phpstan) on the current buffer, whose result depends on other files.
-- ============================================================================
local uv = vim.uv

-- Servers that rely on the client to watch files, and which files they care about
local WATCHED_BY_CLIENT = {
  intelephense = "%.php$",
}

local IGNORED = { "/%.git/", "/node_modules/", "%.sw[a-p]$", "~$", "/4913$" }
local DEBOUNCE_MS = 150

local FileChangeType = vim.lsp.protocol.FileChangeType

local handle ---@type uv.uv_fs_event_t?
local root ---@type string?
local pending = {} ---@type table<string, true>
local timer = assert(uv.new_timer())

local function ignored(path)
  for _, pattern in ipairs(IGNORED) do
    if path:find(pattern) then
      return true
    end
  end
  return false
end

local function notify_servers(paths)
  for _, client in ipairs(vim.lsp.get_clients()) do
    local pattern = WATCHED_BY_CLIENT[client.name]
    if pattern then
      local changes = {}
      for _, path in ipairs(paths) do
        local in_root = not client.root_dir or vim.startswith(path, client.root_dir .. "/")
        if in_root and path:find(pattern) then
          local exists = uv.fs_stat(path) ~= nil
          changes[#changes + 1] = {
            uri = vim.uri_from_fname(path),
            type = exists and FileChangeType.Changed or FileChangeType.Deleted,
          }
        end
      end
      if #changes > 0 then
        client:notify("workspace/didChangeWatchedFiles", { changes = changes })
      end
    end
  end
end

local function flush()
  local paths = vim.tbl_keys(pending)
  pending = {}
  if #paths == 0 then
    return
  end

  -- reload changed buffers (autoread skips buffers with unsaved changes)
  if vim.fn.mode() ~= "c" then
    for _, path in ipairs(paths) do
      local buf = vim.fn.bufnr(path)
      if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
        vim.cmd("silent! checktime " .. buf)
      end
    end
  end

  notify_servers(paths)

  -- other files changed under the current buffer's linters (e.g. phpstan): lint it again
  local lint = package.loaded["lint"]
  if lint and vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= "" then
    lint.try_lint()
  end
end

local function on_change(err, filename)
  if err or not filename or not root then
    return
  end
  local path = vim.fs.normalize(root .. "/" .. filename)
  if ignored(path) then
    return
  end
  pending[path] = true
  timer:stop()
  timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(flush))
end

local function watch(dir)
  dir = vim.fs.normalize(dir)
  if dir == root then
    return
  end
  if handle then
    handle:stop()
    handle:close()
    handle = nil
  end
  -- never watch the whole home directory or the filesystem root
  if dir == "/" or dir == vim.fs.normalize("~") then
    root = nil
    return
  end
  root = dir
  handle = assert(uv.new_fs_event())
  local ok = handle:start(dir, { recursive = true }, on_change)
  if not ok then
    handle:close()
    handle, root = nil, nil
  end
end

watch(vim.fn.getcwd())
vim.api.nvim_create_autocmd("DirChanged", {
  group = vim.api.nvim_create_augroup("ExternalChanges", { clear = true }),
  callback = function()
    watch(vim.fn.getcwd())
  end,
})
