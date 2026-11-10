-- The options of the tests pane that the user changes while working (kept between sessions):
--   parallel   run the test files of one run at the same time
--   workers    how many at once
local M = {}

-- (a test run of the configuration must not touch the options of the real one)
local file = vim.env.NVIM_CONFIG_TESTS and (vim.fn.tempname() .. "-phpunit-options.json")
  or (vim.fn.stdpath("state") .. "/phpunit-options.json")
local MIN, MAX = 2, 16

local values ---@type { parallel: boolean, workers: integer }?

local function load()
  if values then
    return values
  end
  values = { parallel = false, workers = 4 }
  local fd = io.open(file, "r")
  if fd then
    local ok, data = pcall(vim.json.decode, fd:read("*a"))
    fd:close()
    if ok and type(data) == "table" then
      values.parallel = data.parallel == true
      if type(data.workers) == "number" then
        values.workers = math.min(MAX, math.max(MIN, math.floor(data.workers)))
      end
    end
  end
  return values
end

local function save()
  vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
  local fd = io.open(file, "w")
  if fd then
    fd:write(vim.json.encode(values))
    fd:close()
  end
end

function M.parallel()
  return load().parallel
end

function M.workers()
  return load().workers
end

function M.set_parallel(on)
  load().parallel = on and true or false
  save()
end

function M.toggle_parallel()
  M.set_parallel(not M.parallel())
  return M.parallel()
end

--- Change the number of workers by `delta` (kept between MIN and MAX); the first value of a project is
--- the one its .nvim.lua gives (configure({ workers = N })).
function M.set_workers(count)
  load().workers = math.min(MAX, math.max(MIN, math.floor(count)))
  save()
  return values.workers
end

--- Forget what is in memory (the next call reads the file again); for tests.
function M.reload()
  values = nil
end

M.file = file

return M
