-- A very small test framework: test(name, fn), eq / ok / matches, and run().
local M = { tests = {}, passed = 0, failed = 0, cleanups = {} }

-- run after every test, pass or fail (e.g. to close the embedded Neovim a failed test left behind)
function M.on_cleanup(fn)
  M.cleanups[#M.cleanups + 1] = fn
end

function M.test(name, fn)
  M.tests[#M.tests + 1] = { name = name, fn = fn }
end

function M.eq(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(string.format("%sexpected %s, got %s", message and (message .. ": ") or "", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

function M.ok(value, message)
  if not value then
    error(message or "expected a truthy value", 2)
  end
end

function M.matches(pattern, text, message)
  if type(text) ~= "string" or not text:find(pattern) then
    error(string.format("%sexpected %s to match %s", message and (message .. ": ") or "", vim.inspect(text), pattern), 2)
  end
end

function M.run(filter)
  local started = vim.uv.hrtime()
  for _, t in ipairs(M.tests) do
    if not filter or t.name:find(filter, 1, true) then
      local t0 = vim.uv.hrtime()
      local ok, err = xpcall(t.fn, debug.traceback)
      for _, cleanup in ipairs(M.cleanups) do
        pcall(cleanup)
      end
      local ms = math.floor((vim.uv.hrtime() - t0) / 1e6)
      if ok then
        M.passed = M.passed + 1
        print(string.format("  ✓ %s (%dms)", t.name, ms))
      else
        M.failed = M.failed + 1
        print(string.format("  ✗ %s (%dms)\n    %s", t.name, ms, tostring(err):gsub("\n", "\n    ")))
      end
    end
  end
  print(string.format("\n%d passed, %d failed (%.1fs)", M.passed, M.failed, (vim.uv.hrtime() - started) / 1e9))
  return M.failed == 0
end

return M
