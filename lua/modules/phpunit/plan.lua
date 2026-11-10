-- How to run PHPUnit for a position of the test tree (pure functions: no Neovim UI, no neotest).
--
-- The settings mirror the VS Code PHPUnit extension (`.vscode/settings.json` of a project) so the same
-- values can be copied: `command` (with ${php}, ${phpargs}, ${phpunitargs}, ${workspaceFolder}), `paths`
-- (host folder -> folder inside the container) and `args`. Besides them:
--   root          the workspace folder (the tree of tests starts here)
--   projects      sub folders of root that have tests, each with its own phpunit config (default: root alone)
--                 or, when `args` holds `--configuration=<project>/tests.xml` like the VS Code setting, that one
--                 project: the search for tests is limited to it
--   config_files  names of the phpunit config looked for in a project, first one found wins
--   env           environment of the command
local M = {}

local uv = vim.uv

local DEFAULTS = {
  command = "${php} ${phpargs} vendor/bin/phpunit ${phpunitargs}",
  paths = {},
  args = {},
  config_files = { "tests.xml", "phpunit.xml", "phpunit.xml.dist" },
  projects = nil,
  env = nil,
}

local settings = vim.deepcopy(DEFAULTS)
local configured = false

-- the canonical form of a path: no trailing slash, links and the case of the disk resolved
local function norm(path)
  path = vim.fs.normalize(path)
  local real = uv.fs_realpath(path)
  return ((real or path):gsub("/+$", ""))
end
M.norm = norm

local function mapped(map)
  local out = {}
  for host, container in pairs(map or {}) do
    out[norm(host)] = (container:gsub("/+$", ""))
  end
  return out
end

--- Set the project settings (see the top of the file). Called from a project's .nvim.lua.
function M.configure(opts)
  opts = opts or {}
  settings = vim.tbl_extend("force", vim.deepcopy(DEFAULTS), opts)
  settings.root = opts.root and norm(opts.root) or nil
  settings.paths = mapped(opts.paths)
  settings.configs = {}
  configured = opts.root ~= nil

  -- `--configuration=<file>` in args: the project of that file, run with that config
  local args, from_args = {}, {}
  local list = opts.args or {}
  local i = 1
  while i <= #list do
    local arg = list[i]
    local file = arg:match("^%-%-configuration=(.+)$")
    if not file and arg == "--configuration" and list[i + 1] then
      file, i = list[i + 1], i + 1
    end
    if file and settings.root then
      local abs = norm(file:sub(1, 1) == "/" and file or (settings.root .. "/" .. file))
      local project = vim.fs.dirname(abs)
      settings.configs[project] = abs
      from_args[#from_args + 1] = project
    else
      args[#args + 1] = arg
    end
    i = i + 1
  end
  settings.args = args

  local projects = {}
  for _, rel in ipairs(opts.projects or {}) do
    projects[#projects + 1] = norm(settings.root .. "/" .. rel)
  end
  if #projects == 0 then
    projects = from_args
  end
  settings.projects = #projects > 0 and projects or nil
end

function M.reset()
  settings, configured = vim.deepcopy(DEFAULTS), false
end

function M.is_configured()
  return configured
end

function M.get()
  return settings
end

local function under(path, dir)
  return path == dir or path:sub(1, #dir + 1) == dir .. "/"
end
M.under = under

--- A path of the host as the container sees it (unchanged when no folder maps it).
function M.to_container(path)
  path = norm(path)
  local best
  for host in pairs(settings.paths) do
    if under(path, host) and (not best or #host > #best) then
      best = host
    end
  end
  return best and (settings.paths[best] .. path:sub(#best + 1)) or path
end

--- A path of the container as it is on the host (unchanged when no folder maps it).
function M.to_host(path)
  local best, best_host
  for host, container in pairs(settings.paths) do
    if under(path, container) and (not best or #container > #best) then
      best, best_host = container, host
    end
  end
  return best and (best_host .. path:sub(#best + 1)) or path
end

--- The project (a folder with its own phpunit config) a path belongs to; nil when it belongs to none.
function M.project_of(path)
  path = norm(path)
  if settings.projects then
    local best
    for _, project in ipairs(settings.projects) do
      if under(path, project) and (not best or #project > #best) then
        best = project
      end
    end
    return best
  end
  -- no list: the nearest folder up to the root that has a config file
  local dir = uv.fs_stat(path) and uv.fs_stat(path).type == "directory" and path or vim.fs.dirname(path)
  local stop = settings.root
  while dir and dir ~= "/" do
    if M.config_of(dir) then
      return dir
    end
    if dir == stop then
      break
    end
    dir = vim.fs.dirname(dir)
  end
end

--- The phpunit config file of a project folder, nil when it has none.
function M.config_of(project)
  if settings.configs and settings.configs[project] then
    return settings.configs[project]
  end
  for _, name in ipairs(settings.config_files) do
    local file = project .. "/" .. name
    if uv.fs_stat(file) then
      return file
    end
  end
end

--- The projects a position (a file or a folder, absolute path) covers, each with the path to run in it:
--- a file or folder inside a project runs in that project; a folder above projects runs each of them.
---@return { project: string, path: string }[]
function M.targets(path)
  path = norm(path)
  local own = M.project_of(path)
  if own then
    return { { project = own, path = path } }
  end
  local found = {}
  for _, project in ipairs(settings.projects or {}) do
    if under(project, path) then
      found[#found + 1] = { project = project, path = project }
    end
  end
  return found
end

-- ── the command line ──────────────────────────────────────────────────────────────────────────

-- one argument for a POSIX shell
local function sh_quote(arg)
  if arg:match("^[%w_%-%.,:/=@%%+]+$") then
    return arg
  end
  return "'" .. arg:gsub("'", [['\'']]) .. "'"
end
M.sh_quote = sh_quote

-- whether position `pos` of `text` is inside a double-quoted string (the template of a VS Code command
-- wraps the phpunit part in "…" for the shell inside the container)
local function in_double_quotes(text, pos)
  local open, i = false, 1
  while i < pos do
    local c = text:sub(i, i)
    if c == "\\" then
      i = i + 1
    elseif c == '"' then
      open = not open
    end
    i = i + 1
  end
  return open
end

local function dq_escape(text)
  return (text:gsub('([\\"$`])', "\\%1"))
end

--- The command line (for `sh -c`) that runs phpunit with `args`: the template of the settings with its
--- ${…} variables filled in. The arguments are quoted for the innermost shell, and escaped once more
--- when the template puts them inside double quotes.
function M.command(args)
  local all = vim.list_extend(vim.deepcopy(settings.args or {}), args)
  local quoted = {}
  for _, arg in ipairs(all) do
    quoted[#quoted + 1] = sh_quote(arg)
  end
  local joined = table.concat(quoted, " ")
  local values = {
    php = "php",
    phpargs = "",
    phpunitargs = joined,
    workspaceFolder = settings.root or vim.uv.cwd(),
  }
  local text = settings.command
  local out, from = {}, 1
  while true do
    local s, e, name = text:find("%${(%w+)}", from)
    if not s then
      out[#out + 1] = text:sub(from)
      break
    end
    out[#out + 1] = text:sub(from, s - 1)
    local value = values[name]
    if value == nil then
      value = text:sub(s, e)
    elseif in_double_quotes(text, s) then
      value = dq_escape(value)
    end
    out[#out + 1] = value
    from = e + 1
  end
  return (table.concat(out):gsub("%s+$", ""))
end

--- The phpunit arguments (host paths already turned into container paths) to run `target` and write the
--- junit log to `results` (a host path under a mapped folder).
---@param target { project: string, path: string }
---@param results string
---@param test? string|string[] name of one test method, or of several
function M.args(target, results, test)
  local args = {}
  local config = M.config_of(target.project)
  if config then
    args[#args + 1] = "--configuration=" .. M.to_container(config)
  end
  if norm(target.path) ~= target.project then
    args[#args + 1] = M.to_container(target.path)
  end
  args[#args + 1] = "--log-junit=" .. M.to_container(results)
  if type(test) == "table" and #test == 1 then
    test = test[1]
  end
  if test then
    args[#args + 1] = "--filter"
    local names = type(test) == "table" and ("(" .. table.concat(test, "|") .. ")") or test
    args[#args + 1] = "::" .. names .. "( with data set .*)?$"
  end
  return args
end

--- Where the junit log of a run goes: a folder the container sees too when paths are mapped, else tmp.
function M.results_dir()
  if next(settings.paths) and settings.root then
    for host in pairs(settings.paths) do
      if under(settings.root, host) or under(host, settings.root) then
        return host .. "/.neotest-results"
      end
    end
  end
  return vim.fn.stdpath("run") .. "/neotest-phpunit"
end

return M
