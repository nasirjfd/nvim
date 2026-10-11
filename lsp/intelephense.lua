-- PHP language server; a license key is optional.
local function get_license()
  local home = vim.env.HOME
  if not home then
    return nil
  end

  local path = vim.fs.joinpath(home, "intelephense", "license.txt")
  local f = io.open(path, "rb")
  if not f then
    return nil
  end

  local content = f:read("*a")
  f:close()
  local license = string.gsub(content, "%s+", "")
  return license ~= "" and license or nil
end

local license = get_license()

return {
  cmd = { "intelephense", "--stdio" },
  filetypes = { "php", "blade" },
  -- Composer "path repository" monorepos (e.g. supernova-env-dev) nest
  -- independent git repos under vendor/<pkg>, each with its own
  -- composer.json/.git. Plain root_markers would root intelephense at the
  -- nearest one of those instead of the real project root, walling it off
  -- from the rest of the codebase and breaking cross-package go-to-def.
  -- Climb past any vendor/ segment before searching for markers.
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    local outer = fname:match("^(.-)/vendor/") or fname
    on_dir(vim.fs.root(outer, { "composer.json", ".git" }))
  end,
  -- Intelephense can otherwise ask Neovim to watch the entire 3 GB vendor
  -- tree, exceeding the system's file watcher limit.
  capabilities = {
    workspace = {
      didChangeWatchedFiles = { dynamicRegistration = false },
    },
  },
  init_options = license and { licenceKey = license } or nil,
}
