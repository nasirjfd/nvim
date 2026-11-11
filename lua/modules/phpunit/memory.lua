-- What each test did last time (passed, failed with its message), kept between sessions in
-- stdpath("state")/phpunit-results.json, per project root. After a restart the pane, the signs and the messages show
-- it again, and "run the failed tests" runs exactly the ones that failed.
--
-- neotest keeps results only in memory; they are put back into its state (the client's `_state`, private API) as
-- tests are found, so everything that reads neotest's results shows them without knowing about this file.
local M = {}

local uv = vim.uv

local path = vim.env.NVIM_CONFIG_TESTS and (vim.fn.tempname() .. "-phpunit-results.json")
  or (vim.fn.stdpath("state") .. "/phpunit-results.json")
local MAX_MESSAGE = 1500 -- characters kept of a failure message (the trace is not needed)

local data ---@type table<string, table<string, { status: string, short?: string, errors?: table[] }>>?

--- Use another file (the automated tests give two sessions the same one).
function M.set_file(file)
  path = file
  data = nil
end

local function load()
  if data then
    return data
  end
  data = {}
  local fd = io.open(path, "r")
  if fd then
    local ok, decoded = pcall(vim.json.decode, fd:read("*a"))
    fd:close()
    if ok and type(decoded) == "table" then
      data = decoded
    end
  end
  return data
end

local function write()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local tmp = path .. ".tmp"
  local fd = io.open(tmp, "w")
  if fd then
    fd:write(vim.json.encode(data))
    fd:close()
    os.rename(tmp, path) -- never a half-written file
  end
end

local function trim(text)
  if type(text) == "string" and #text > MAX_MESSAGE then
    return text:sub(1, MAX_MESSAGE)
  end
  return text
end

local function file_of(id)
  return id:match("^(.-)::") or id
end

--- What is kept of a result.
local function keep(result)
  local entry = { status = result.status }
  if result.status == "failed" then
    entry.short = trim(result.short)
    entry.errors = {}
    for i, err in ipairs(result.errors or {}) do
      if i > 3 then
        break
      end
      entry.errors[#entry.errors + 1] = { line = err.line, message = trim(err.message) }
    end
  end
  if result.datasets then
    entry.datasets = {}
    for _, set in ipairs(result.datasets) do
      local kept = { label = set.label, status = set.status }
      if set.status == "failed" then
        kept.short = trim(set.short) and trim(set.short):sub(1, 300)
      end
      entry.datasets[#entry.datasets + 1] = kept
    end
  end
  return entry
end

--- Remember the results of the tests of `root`: `results` by position id, `is_test(id)` tells a test position from
--- a file or folder. What is not there stays as it was, except tests whose file no longer exists.
function M.remember(root, results, is_test)
  local all = load()
  local mine = all[root] or {}
  for id, result in pairs(results) do
    if is_test(id) and (result.status == "passed" or result.status == "failed" or result.status == "skipped") then
      mine[id] = keep(result)
    end
  end
  for id in pairs(mine) do
    if not uv.fs_stat(file_of(id)) then
      mine[id] = nil
    end
  end
  all[root] = mine
  data = all
  write()
end

--- The remembered results of `root` (a copy).
function M.recall(root)
  return vim.deepcopy(load()[root] or {})
end

return M
