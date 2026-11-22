-- A very small test framework: test(name, fn), eq / ok / matches, and run().
local M = { tests = {}, passed = 0, failed = 0, cleanups = {}, file_ms = {} }

-- the real data directory (plugins, Mason tools, parsers), and what in it each test gets fresh instead
M.real_data = (vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share")) .. "/nvim"
M.data_private = { snacks = true, undo = true, scratch = true, shada = true }

-- the real cache directory; each test gets its own with everything linked in except "luac": Neovim's
-- bytecode cache keeps one file per loaded Lua file path and never deletes any, and every test loads the
-- plugins from its own temporary path, so a shared one grew by millions of files
M.real_cache = (vim.env.XDG_CACHE_HOME or (vim.env.HOME .. "/.cache")) .. "/nvim"
M.cache_private = { luac = true }

-- run after every test, pass or fail (e.g. to close the embedded Neovim a failed test left behind)
function M.on_cleanup(fn)
  M.cleanups[#M.cleanups + 1] = fn
end

function M.test(name, fn)
  M.tests[#M.tests + 1] = { name = name, fn = fn, file = M.file }
end

function M.eq(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(
      string.format(
        "%sexpected %s, got %s",
        message and (message .. ": ") or "",
        vim.inspect(expected),
        vim.inspect(actual)
      ),
      2
    )
  end
end

function M.ok(value, message)
  if not value then
    error(message or "expected a truthy value", 2)
  end
end

function M.matches(pattern, text, message)
  if type(text) ~= "string" or not text:find(pattern) then
    error(
      string.format(
        "%sexpected %s to match %s",
        message and (message .. ": ") or "",
        vim.inspect(text),
        pattern
      ),
      2
    )
  end
end

function M.run(filter)
  local started = vim.uv.hrtime()
  for _, t in ipairs(M.tests) do
    if not t.skip and (not filter or t.name:find(filter, 1, true)) then
      local t0 = vim.uv.hrtime()
      -- Every test starts with an empty state directory (inherited by the editors it starts): pins,
      -- hidden folders, phpunit options/results and swap files of one test never reach another one,
      -- nor the real editor's. Two editors of one test (a restart) share it.
      local state = vim.fn.tempname() .. "-state"
      vim.fn.mkdir(state, "p")
      vim.env.XDG_STATE_HOME = state
      -- The data directory holds the plugins (shared, read only) but also files the editor writes: the
      -- search history database (snacks/picker-frecency, a SQLite file two workers cannot write at the
      -- same moment), undo files, scratch buffers. Each test gets its own, with the rest linked in.
      local data = state .. "/data"
      vim.fn.mkdir(data .. "/nvim", "p")
      for _, name in ipairs(vim.fn.readdir(M.real_data)) do
        if not M.data_private[name] then
          vim.uv.fs_symlink(M.real_data .. "/" .. name, data .. "/nvim/" .. name)
        end
      end
      vim.env.XDG_DATA_HOME = data
      local cache = state .. "/cache"
      vim.fn.mkdir(cache .. "/nvim", "p")
      for _, name in
        ipairs(vim.fn.isdirectory(M.real_cache) == 1 and vim.fn.readdir(M.real_cache) or {})
      do
        if not M.cache_private[name] then
          vim.uv.fs_symlink(M.real_cache .. "/" .. name, cache .. "/nvim/" .. name)
        end
      end
      vim.env.XDG_CACHE_HOME = cache
      local ok, err = xpcall(t.fn, debug.traceback)
      for _, cleanup in ipairs(M.cleanups) do
        pcall(cleanup)
      end
      local ms = math.floor((vim.uv.hrtime() - t0) / 1e6)
      vim.fn.delete(state, "rf")
      if t.file then
        M.file_ms[t.file] = (M.file_ms[t.file] or 0) + ms
      end
      if ok then
        M.passed = M.passed + 1
        print(string.format("  ✓ %s (%dms)", t.name, ms))
      else
        M.failed = M.failed + 1
        print(
          string.format("  ✗ %s (%dms)\n    %s", t.name, ms, tostring(err):gsub("\n", "\n    "))
        )
      end
    end
  end
  print(
    string.format(
      "\n%d passed, %d failed (%.1fs)",
      M.passed,
      M.failed,
      (vim.uv.hrtime() - started) / 1e9
    )
  )
  return M.failed == 0
end

return M
