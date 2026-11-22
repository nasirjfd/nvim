-- What intelephense indexes in a project rooted in a big vendor/ folder: the packages the pickers show (not ignored,
-- not hidden: the project's .ignore / .gitignore, read by fd) plus every package they depend on (composer's
-- installed.json, `require` followed recursively, and their own `require-dev`). Everything else under the root is
-- excluded, so intelephense keeps no index for code nothing of yours uses (supernova: 24k of 50k files indexed, about
-- half the memory), while go-to-definition, types and completion into the dependencies keep working.
--
-- Used from a project's .nvim.lua:
--   vim.lsp.config("intelephense", { settings = { intelephense = { files = {
--     exclude = require("core.intelephense-scope").excludes(root) } } } })
local M = {}

local uv = vim.uv

-- intelephense's own defaults (a setting replaces them)
M.DEFAULTS = {
  "**/.git/**",
  "**/.svn/**",
  "**/.hg/**",
  "**/CVS/**",
  "**/.DS_Store/**",
  "**/node_modules/**",
  "**/bower_components/**",
  "**/vendor/**/{Tests,tests}/**",
  "**/.history/**",
  "**/vendor/**/vendor/**",
}

local function read(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local text = fd:read("*a")
  fd:close()
  return text
end

local function mtime(path)
  local stat = uv.fs_stat(path)
  return stat and (stat.mtime.sec .. "." .. stat.mtime.nsec) or "-"
end

local function installed_json(root)
  for _, path in ipairs({
    root .. "/composer/installed.json",
    root .. "/vendor/composer/installed.json",
  }) do
    if uv.fs_stat(path) then
      return path
    end
  end
end

--- The packages (vendor/name) that fd lists under `root`: the ones not ignored and not hidden.
function M.visible_packages(root)
  local out = vim
    .system({ "fd", "--type", "d", "--exact-depth", "2", ".", root }, { text = true })
    :wait()
  local found = {}
  for line in (out.stdout or ""):gmatch("[^\n]+") do
    local rel = line:sub(#root + 2):gsub("/$", "")
    found[rel] = true
  end
  return found
end

--- The packages to index: `visible` and everything they need (pure, for tests).
---@param packages { name: string, require?: table, ["require-dev"]?: table }[]
---@param visible table<string, boolean>
---@return table<string, boolean>
function M.closure(packages, visible)
  local by_name = {}
  for _, p in ipairs(packages) do
    by_name[p.name] = p
  end
  local keep, todo = {}, {}
  local function add(name)
    if by_name[name] and not keep[name] then
      keep[name] = true
      todo[#todo + 1] = name
    end
  end
  for name in pairs(visible) do
    add(name)
    for dep in pairs((by_name[name] or {})["require-dev"] or {}) do
      add(dep) -- a visible package's tests need its dev tools (phpunit)
    end
  end
  while #todo > 0 do
    local p = by_name[table.remove(todo)]
    for dep in pairs(p.require or {}) do
      add(dep)
    end
  end
  return keep
end

-- (the automated tests never touch the real one)
local cache_file = vim.env.NVIM_CONFIG_TESTS and (vim.fn.tempname() .. "-intelephense-scope.json")
  or (vim.fn.stdpath("state") .. "/intelephense-scope.json")

--- The exclude globs for intelephense in `root` (its defaults plus every package nothing visible needs), or nil when
--- `root` has no composer metadata (then intelephense keeps its defaults).
function M.excludes(root)
  root = vim.fs.normalize(root)
  local json = installed_json(root)
  if not json then
    return nil
  end
  -- what the answer depends on: recomputed only when one of these changes
  local key = table.concat({
    root,
    mtime(json),
    mtime(root .. "/.ignore"),
    mtime(root .. "/.gitignore"),
    mtime(vim.fs.dirname(root) .. "/.gitignore"),
  }, "|")
  local ok, cached = pcall(vim.json.decode, read(cache_file) or "")
  if ok and type(cached) == "table" and cached[root] and cached[root].key == key then
    return cached[root].excludes
  end

  local decoded_ok, decoded = pcall(vim.json.decode, read(json) or "")
  if not decoded_ok or type(decoded) ~= "table" then
    return nil
  end
  local packages = decoded.packages or decoded
  local keep = M.closure(packages, M.visible_packages(root))
  if next(keep) == nil then
    return nil -- nothing visible: index as before rather than nothing
  end
  local excludes = vim.deepcopy(M.DEFAULTS)
  local names = {}
  for _, p in ipairs(packages) do
    if not keep[p.name] and uv.fs_stat(root .. "/" .. p.name) then
      names[#names + 1] = p.name
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    excludes[#excludes + 1] = root .. "/" .. name .. "/**"
  end

  cached = (ok and type(cached) == "table") and cached or {}
  cached[root] = { key = key, excludes = excludes }
  vim.fn.mkdir(vim.fs.dirname(cache_file), "p")
  local fd = io.open(cache_file, "w")
  if fd then
    fd:write(vim.json.encode(cached))
    fd:close()
  end
  return excludes
end

return M
