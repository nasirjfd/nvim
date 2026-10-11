-- PHP language server with Intelephense license key
local function get_license()
  local path = os.getenv("HOME") .. "/intelephense/license.txt"
  local f = assert(io.open(path, "rb"))
  local content = f:read("*a")
  f:close()
  return string.gsub(content, "%s+", "")
end

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
  init_options = {
    licenceKey = get_license(),
  },
}
