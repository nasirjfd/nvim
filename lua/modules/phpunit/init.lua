-- PHPUnit for neotest, the way a project runs it: through a command template that may go into a Docker
-- container (see plan.lua for the settings, copied from the VS Code PHPUnit extension), one phpunit config
-- per project, and the results mapped back from container paths to the files on this machine.
--
-- It wraps olimorris/neotest-phpunit (finding the tests in a file, reading the junit log) and replaces what
-- cannot work through a container: the command, the place of the junit log and the paths in it.
--
-- A project turns it on in its `.nvim.lua`:
--   require("modules.phpunit").configure({ root = ..., command = ..., paths = { [host] = container }, ... })
-- Without that it runs `vendor/bin/phpunit` locally, like neotest-phpunit does.
local plan = require("modules.phpunit.plan")

local M = { configure = plan.configure, plan = plan }

local function base()
  return require("neotest-phpunit")
end

local ADAPTER = { name = "phpunit" }

-- directories never searched for tests
local SKIP = { vendor = true, node_modules = true, [".git"] = true, cache = true, [".neotest-results"] = true }

function ADAPTER.root(dir)
  if not plan.is_configured() then
    return base().root(dir)
  end
  local root = plan.get().root
  if root and plan.under(plan.norm(dir), root) then
    return root
  end
end

function ADAPTER.is_test_file(path)
  -- a class called just "Test" is not a test case
  if not vim.endswith(path, "Test.php") or vim.fs.basename(path) == "Test.php" then
    return false
  end
  return not plan.is_configured() or plan.project_of(path) ~= nil
end

---@param name string
---@param rel_path string
---@param root string
function ADAPTER.filter_dir(name, rel_path, root)
  if SKIP[name] then
    return false
  end
  local projects = plan.get().projects
  if not (plan.is_configured() and projects) then
    return base().filter_dir(name)
  end
  local abs = plan.norm(root .. "/" .. rel_path)
  for _, project in ipairs(projects) do
    -- inside a project, or on the way to one
    if plan.under(abs, project) or plan.under(project, abs) then
      return true
    end
  end
  return false
end

function ADAPTER.discover_positions(path)
  return base().discover_positions(path)
end

---@param args neotest.RunArgs
function ADAPTER.build_spec(args)
  local nio = require("nio")
  local position = args.tree:data()
  local targets = plan.targets(position.path)
  if #targets == 0 then
    return nil
  end
  local dir = plan.results_dir()
  vim.fn.mkdir(dir, "p")
  local specs = {}
  for index, target in ipairs(targets) do
    local results = string.format("%s/%d-%d-%s.xml", dir, vim.uv.os_getpid(), index, nio.fn.tempname():match("[^/]+$"))
    -- one test, or the tests of a file that the pane picked (the ones that failed last time)
    local only = args.extra_args and args.extra_args.only
    local test = position.type == "test" and position.name or only
    local argv = plan.args(target, results, test)
    specs[#specs + 1] = {
      command = { "/bin/sh", "-c", plan.command(argv) },
      cwd = plan.get().root or vim.uv.cwd(),
      env = args.env or plan.get().env,
      context = { results_path = results },
      strategy = nil,
    }
  end
  return specs
end

local function failed(position_id, message, output)
  return { [position_id] = { status = "failed", short = message, output = output } }
end

---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
function ADAPTER.results(spec, result, tree)
  local lib = require("neotest.lib")
  local path = spec.context.results_path
  local ok, data = pcall(lib.files.read, path)
  pcall(vim.uv.fs_unlink, path)
  pcall(vim.uv.fs_rmdir, vim.fs.dirname(path)) -- only when nothing else is in it
  local id = tree:data().id
  if not ok or not data or data == "" then
    return failed(id, "PHPUnit wrote no results (exit code " .. tostring(result.code) .. "), see the output", result.output)
  end
  -- the log names the files as the container sees them
  for host, container in pairs(plan.get().paths) do
    data = data:gsub(vim.pesc(container) .. "/", function()
      return host .. "/"
    end)
  end
  local got_ok, results = pcall(require("modules.phpunit.junit").from_text, data)
  if not got_ok then
    return failed(id, "PHPUnit's results could not be read", result.output)
  end
  for _, one in pairs(results) do
    one.output = result.output -- the whole run is the output of every test in it
  end
  if next(results) == nil then
    return failed(id, "PHPUnit ran no tests, see the output", result.output)
  end
  return results
end

M.adapter = ADAPTER

-- ── the tests pane (Cmd+Shift+T) ───────────────────────────────────────────────────────────────
M.toggle = function()
  require("modules.phpunit.pane").toggle()
end

return M
