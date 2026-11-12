-- The options of the tests pane that the user changes while working (kept between sessions):
--   parallel   run the test files of one run at the same time
--   (how many at once is fixed: WORKERS, or the project's max_workers when that is lower)
--   flat       list every test on its own (true) instead of folder -> file -> tests
local M = {}

-- (a test run of the configuration must not touch the options of the real one)
local file = vim.env.NVIM_CONFIG_TESTS and (vim.fn.tempname() .. "-phpunit-options.json")
  or (vim.fn.stdpath("state") .. "/phpunit-options.json")
local MIN, MAX = 2, 64
local WORKERS = 10 -- at a time: more is better, so it is not a setting
local limit = MAX -- what the project can run at once (configure({ max_workers = N }))

local values ---@type { parallel: boolean, workers: integer }?

local function load()
  if values then
    return values
  end
  values = { parallel = false, workers = WORKERS, flat = false }
  local fd = io.open(file, "r")
  if fd then
    local ok, data = pcall(vim.json.decode, fd:read("*a"))
    fd:close()
    if ok and type(data) == "table" then
      values.parallel = data.parallel == true
      values.flat = data.flat == true
    end
  end
  return values
end

local function save()
  vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
  local fd = io.open(file, "w")
  if fd then
    fd:write(vim.json.encode({ parallel = values.parallel, flat = values.flat }))
    fd:close()
  end
end

function M.parallel()
  return load().parallel
end

function M.flat()
  return load().flat
end

function M.set_flat(on)
  load().flat = on and true or false
  save()
end

function M.toggle_flat()
  load().flat = not values.flat
  save()
  return values.flat
end

function M.workers()
  return math.min(load().workers, limit)
end

--- The most workers the project can use (its databases, say); the number of workers never goes above it.
function M.set_limit(count)
  limit = math.min(MAX, math.max(MIN, math.floor(count or MAX)))
end

function M.limit()
  return limit
end

function M.set_parallel(on)
  load().parallel = on and true or false
  save()
end

function M.toggle_parallel()
  M.set_parallel(not M.parallel())
  return M.parallel()
end

--- Set the number of workers for this session (tests use it; it is not saved and no key changes it).
function M.set_workers(count)
  load().workers = math.min(limit, math.max(MIN, math.floor(count)))
  return values.workers
end

--- Forget what is in memory (the next call reads the file again); for tests.
function M.reload()
  values = nil
end

M.file = file

return M
