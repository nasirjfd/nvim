-- Running tests the way the pane and the keys want it: the position under the cursor, a file, a folder, all of
-- them, only what failed last time, the last run again; one after the other or several test files at once.
--
-- neotest does the work of each run (command, results, signs, output); this decides which runs there are.
-- PHPUnit cannot run one run in parallel, so "parallel" means one phpunit per test file, `workers` of them
-- at a time.
local options = require("modules.phpunit.options")

local M = {}

local last ---@type { ids: string[], only?: table<string, string[]> }?
local stopped = false

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Tests" })
end

local function pane()
  return require("modules.phpunit.pane")
end

-- One neotest run of `id` (a position id), waiting until it is over. `only` lists the test names to run in a
-- file (the build_spec of the adapter turns them into --filter).
local function run_one(id, only)
  local args = { id, concurrent = false }
  if only then
    args.extra_args = { only = only }
  end
  require("neotest").run.run(args)
end

-- Run all `jobs` (functions): in turn, or `workers` at a time when parallel is on.
local function run_jobs(jobs)
  local nio = require("nio")
  stopped = false
  if options.parallel() and #jobs > 1 then
    local gate = nio.control.semaphore(options.workers())
    local tasks = {}
    for _, job in ipairs(jobs) do
      tasks[#tasks + 1] = function()
        gate.with(function()
          if not stopped then
            job()
          end
        end)
      end
    end
    nio.gather(tasks)
  else
    for _, job in ipairs(jobs) do
      if stopped then
        break
      end
      job()
    end
  end
end

--- Run the positions `ids` (files, folders or tests). A folder with several test files is split into its
--- files when parallel is on.
---@param ids string[]
---@param only? table<string, string[]> test names to run, by file
function M.run(ids, only)
  local nio = require("nio")
  last = { ids = ids, only = only }
  nio.run(function()
    local jobs = {}
    for _, id in ipairs(ids) do
      local files = options.parallel() and pane().files_under(id) or nil
      if files and #files > 1 then
        for _, file in ipairs(files) do
          jobs[#jobs + 1] = function()
            run_one(file, only and only[file])
          end
        end
      else
        jobs[#jobs + 1] = function()
          run_one(id, only and only[id])
        end
      end
    end
    run_jobs(jobs)
  end)
end

--- All the tests.
function M.run_all()
  local root = pane().root_id()
  if not root then
    return notify("The tests are not found yet", vim.log.levels.WARN)
  end
  M.run({ root })
end

--- The tests of the file open in the current window.
function M.run_file()
  local file = vim.api.nvim_buf_get_name(0)
  local id = pane().file_id(file)
  if not id then
    return notify("No tests in this file", vim.log.levels.WARN)
  end
  M.run({ id })
end

--- The test under the cursor (the last one that starts above it); the file when there is none.
function M.run_nearest()
  local id = pane().nearest(vim.api.nvim_buf_get_name(0), vim.api.nvim_win_get_cursor(0)[1] - 1)
  if not id then
    -- the pane does not know this file yet (neotest is still looking through the project, or the pane was
    -- never opened): neotest reads the file in this window itself and runs the test under the cursor
    require("neotest").run.run({ concurrent = false })
    return
  end
  M.run({ id })
end

--- Only the tests that failed in their last run.
function M.run_failed()
  local only, ids = pane().failed()
  if #ids == 0 then
    return notify("No failed tests")
  end
  M.run(ids, only)
end

--- The last run again, with the same positions.
function M.run_last()
  if not last then
    return notify("No tests have run yet", vim.log.levels.WARN)
  end
  M.run(last.ids, last.only)
end

--- Stop what runs now (and the files waiting for a free worker).
function M.stop()
  stopped = true
  local nio = require("nio")
  nio.run(function()
    for _, id in ipairs(pane().running_ids()) do
      pcall(require("neotest").run.stop, id)
    end
  end)
end

return M
