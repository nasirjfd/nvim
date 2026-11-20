-- Run with:  tests/run.sh [options] [name filter]     (nvim -l tests/run.lua)
--
--   tests/run.sh                 every spec, in parallel workers (the default; about a minute)
--   tests/run.sh "http pane"     only the tests whose name contains the text
--   tests/run.sh --changed       only the specs related to the files changed since HEAD (and new files)
--   tests/run.sh --serial        one process, one spec after the other (the old way; for debugging)
--   tests/run.sh --jobs 4        the number of workers
--
-- Every spec drives a real Neovim with this configuration, embedded and rendered, so what is asserted is
-- what is on the screen. Each test gets its own empty state directory (stdpath("state"): pins, hidden
-- folders, phpunit options and results, swap files), so tests cannot leak into each other or into the
-- real editor, and workers can run side by side.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/tests/?.lua;" .. root .. "/lua/?.lua;" .. package.path
vim.env.NVIM_CONFIG_TESTS = "1" -- no network, no automatic plugin updates (lua/core/lazy.lua)

local DURATIONS = root .. "/tests/.durations.json" -- per machine, not committed (.gitignore)

local opts =
  { jobs = nil, serial = false, changed = false, filter = nil, files = nil, worker = false }
do
  local i = 1
  while arg and i <= #arg do
    local a = arg[i]
    if a == "--serial" then
      opts.serial = true
    elseif a == "--changed" then
      opts.changed = true
    elseif a == "--jobs" then
      i = i + 1
      opts.jobs = tonumber(arg[i])
    elseif a == "--worker" then
      opts.worker = true
    elseif a == "--files" then
      i = i + 1
      opts.files = vim.split(arg[i], ",", { plain = true })
    else
      opts.filter = a
    end
    i = i + 1
  end
end

local function all_specs()
  return vim.fn.sort(vim.fn.glob(root .. "/tests/specs/*.lua", false, true))
end

-- ── one process running some spec files (a worker, or the whole run with --serial) ─────────────
local function run_here(files, filter)
  local lib = require("lib")
  for _, entry in ipairs(files) do
    -- "file.lua#k/n": only every n-th test of the file, starting at the k-th (a long file is split
    -- over several workers)
    local file, k, n = entry:match("^(.-)#(%d+)/(%d+)$")
    file = file or entry
    lib.file = vim.fn.fnamemodify(file, ":t")
    local first = #lib.tests + 1
    dofile(file)
    if k then
      for i = first, #lib.tests do
        if (i - first) % tonumber(n) ~= tonumber(k) then
          lib.tests[i].skip = true
        end
      end
    end
  end
  lib.file = nil
  local ok = lib.run(filter)
  -- per-file durations for the scheduler of the next run
  for file, ms in pairs(lib.file_ms) do
    print(("@duration %s %d"):format(file, ms))
  end
  return ok
end

if opts.worker then
  local ok = run_here(opts.files or {}, opts.filter)
  vim.cmd(ok and "qa!" or "cq!")
  return
end

-- ── which specs ──────────────────────────────────────────────────────────────────────────────────
local function read_durations()
  local fd = io.open(DURATIONS, "r")
  if not fd then
    return {}
  end
  local ok, data = pcall(vim.json.decode, fd:read("*a"))
  fd:close()
  return ok and type(data) == "table" and data or {}
end

-- The specs related to the files changed since HEAD: a changed spec itself, and every spec that
-- names a changed Lua module (or its file name). A change to the configuration's core (init.lua,
-- lazy.lua, the plugin specs, the test harness) can touch anything: then every spec runs.
local function changed_specs()
  local out =
    vim.fn.systemlist({ "git", "-C", root, "status", "--porcelain", "--untracked-files=all" })
  local changed = {}
  for _, line in ipairs(out) do
    local path = line:sub(4):gsub("^.* %-> ", "")
    changed[#changed + 1] = path
  end
  local specs = all_specs()
  if #changed == 0 then
    return {}, "nothing changed"
  end
  local everything = {
    "^init%.lua$",
    "^lua/core/init%.lua$",
    "^lua/core/lazy%.lua$",
    "^lua/plugins/",
    "^tests/[^/]+%.lua$",
    "^lazy%-lock%.json$",
  }
  local picked = {}
  for _, path in ipairs(changed) do
    for _, pattern in ipairs(everything) do
      if path:find(pattern) then
        return specs, path .. " can affect every spec"
      end
    end
  end
  local texts = {}
  for _, spec in ipairs(specs) do
    local fd = io.open(spec, "r")
    texts[spec] = fd and fd:read("*a") or ""
    if fd then
      fd:close()
    end
  end
  for _, path in ipairs(changed) do
    if path:find("^tests/specs/.+%.lua$") then
      picked[root .. "/" .. path] = true
    elseif path:find("%.lua$") then
      local module = path:gsub("^lua/", ""):gsub("%.lua$", ""):gsub("/init$", ""):gsub("/", ".")
      local base = vim.fn.fnamemodify(path, ":t:r")
      if base == "init" then
        base = vim.fn.fnamemodify(path, ":h:t")
      end
      for spec, text in pairs(texts) do
        if text:find(module, 1, true) or (#base > 3 and text:find(base, 1, true)) then
          picked[spec] = true
        end
      end
    end
  end
  local list = vim.tbl_keys(picked)
  table.sort(list)
  return list, (#list == 0) and "no spec covers the changed files" or nil
end

local files = all_specs()
if opts.changed then
  local why
  files, why = changed_specs()
  if why then
    print("--changed: " .. why)
  end
  if #files == 0 then
    print("0 passed, 0 failed (no spec to run)")
    vim.cmd("qa!")
    return
  end
  print(("--changed: %d spec file(s): %s"):format(
    #files,
    table.concat(
      vim.tbl_map(function(f)
        return vim.fn.fnamemodify(f, ":t")
      end, files),
      " "
    )
  ))
end

if opts.serial then
  local ok = run_here(files, opts.filter)
  vim.cmd(ok and "qa!" or "cq!")
  return
end

-- ── parallel: workers, each a set of spec files of about the same total duration ────────────────
local durations = read_durations()
local cpus = #(vim.uv.cpu_info() or {}) > 0 and #vim.uv.cpu_info() or 4
-- the workers mostly wait on their editors (measured: about 4 of 10 cores busy), so a few more
-- than the cores; past that, timing-sensitive specs start to fail
local jobs = math.max(1, math.min(opts.jobs or math.max(2, cpus + 2), #files))
local sorted = vim.deepcopy(files)
local function cost(file)
  return durations[vim.fn.fnamemodify(file, ":t")] or 5000
end
table.sort(sorted, function(a, b)
  return cost(a) > cost(b)
end)
-- A file longer than a worker's share is split into parts (every n-th test), so one long spec file
-- does not decide how long the whole run takes.
local total = 0
for _, file in ipairs(sorted) do
  total = total + cost(file)
end
-- (half a worker's share: smaller pieces let the queue below even out the workers' ends)
local share = total / jobs / 2
local parts = {}
for _, file in ipairs(sorted) do
  local n = math.max(1, math.min(12, math.ceil(cost(file) / share)))
  if n == 1 or opts.filter then
    parts[#parts + 1] = { name = file, cost = cost(file) }
  else
    for k = 0, n - 1 do
      parts[#parts + 1] = { name = ("%s#%d/%d"):format(file, k, n), cost = cost(file) / n }
    end
  end
end
table.sort(parts, function(a, b)
  return a.cost > b.cost
end)

local started = vim.uv.hrtime()
local passed, failed, running = 0, 0, 0
local measured = {}
local failures = {}
-- A queue, longest piece first: whenever a worker finishes it takes the next piece, so no worker idles
-- while another still has a list to get through (a fixed split goes wrong as soon as durations change).
local next_part = 1
local function spawn()
  if next_part > #parts then
    return
  end
  local part = parts[next_part].name
  next_part = next_part + 1
  do
    running = running + 1
    local args = {
      vim.v.progpath,
      "--headless",
      "--noplugin",
      "-u",
      "NONE",
      "-i",
      "NONE",
      "-l",
      root .. "/tests/run.lua",
      "--worker",
      "--files",
      part,
    }
    if opts.filter then
      args[#args + 1] = opts.filter
    end
    vim.system(args, { text = true, cwd = root }, function(result)
      vim.schedule(function()
        local text = (result.stdout or "") .. (result.stderr or "")
        local p, f = text:match("\n(%d+) passed, (%d+) failed")
        passed, failed = passed + (tonumber(p) or 0), failed + (tonumber(f) or 0)
        if not p then
          failed = failed + 1
          failures[#failures + 1] = "worker crashed:\n" .. text
        end
        local shown = {}
        for line in (text .. "\n"):gmatch("(.-)\n") do
          local file, ms = line:match("^@duration (%S+) (%d+)$")
          if file then
            measured[file] = (measured[file] or 0) + tonumber(ms) -- the parts of a split file add up
          elseif line:find("^%s+✓") then
            shown[#shown + 1] = line
          elseif
            not line:find("^%d+ passed, %d+ failed")
            and not line:find("^%d%d_.*%.lua$")
            and line ~= ""
          then
            shown[#shown + 1] = line
          end
        end
        print(table.concat(shown, "\n"))
        -- a failure with its message, repeated at the end where it is easy to find
        local current
        for line in (text .. "\n"):gmatch("(.-)\n") do
          if line:find("^%s+✗") then
            current = { line }
            failures[#failures + 1] = current
          elseif current and line:find("^    ") then
            current[#current + 1] = line
          elseif not line:find("^    ") then
            current = nil
          end
        end
        running = running - 1
        spawn()
      end)
    end)
  end
end
for _ = 1, jobs do
  spawn()
end
vim.wait(30 * 60 * 1000, function()
  return running == 0 and next_part > #parts
end, 50)

-- remember how long each file took, for balancing the next run (a full run only: a filter or a subset
-- does not measure whole files)
if not opts.filter and not opts.changed and next(measured) then
  local merged = read_durations()
  for file, ms in pairs(measured) do
    merged[file] = ms
  end
  local keys = vim.tbl_keys(merged)
  table.sort(keys)
  local lines = {}
  for _, key in ipairs(keys) do
    lines[#lines + 1] = ('  "%s": %d'):format(key, merged[key])
  end
  local fd = io.open(DURATIONS, "w")
  if fd then
    fd:write("{\n" .. table.concat(lines, ",\n") .. "\n}\n")
    fd:close()
  end
end

if #failures > 0 then
  print("\nFailures:")
  for _, f in ipairs(failures) do
    print(type(f) == "table" and table.concat(f, "\n") or f)
  end
end
print(
  string.format(
    "\n%d passed, %d failed (%.1fs, %d workers)",
    passed,
    failed,
    (vim.uv.hrtime() - started) / 1e9,
    jobs
  )
)
vim.cmd(failed == 0 and "qa!" or "cq!")
