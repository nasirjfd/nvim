-- A failure message of PHPUnit's junit log, taken apart (pure): the test's name, the message, the expected/actual
-- diff, the stack trace. PHPUnit 9 writes it as
--
--   Class::method[ with data set "x" (args)]
--   RuntimeException: boom                       (an error)  /  Failed asserting that ...  (a failure)
--   --- Expected                                 (a comparison: a unified diff of the two values)
--   +++ Actual
--   @@ @@
--   -'a'
--   +'b'
--                                                (a blank line)
--   /path/src/Foo.php:20                         (the trace, innermost first, PHPUnit's own frames left out)
--   /path/tests/FooTest.php:12
--
--   Caused by                                    (a previous exception, the same again)
--   ...
local M = {}

local function split(text)
  local out = {}
  for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
    out[#out + 1] = line
  end
  while #out > 0 and vim.trim(out[#out]) == "" do
    out[#out] = nil
  end
  return out
end

--- `/path/file.php:12` -> path, 12
function M.frame_of(line)
  local file, n = vim.trim(line):match("^(/.+%.%w+):(%d+)$")
  if file then
    return file, tonumber(n)
  end
end

--- Whether a file is the project's own code (not a dependency): under `root` and not in a vendor folder inside it.
function M.is_project_file(file, root)
  if root and root ~= "" then
    root = root:gsub("/$", "")
    if file:sub(1, #root + 1) ~= root .. "/" then
      return false
    end
    file = file:sub(#root + 2)
  end
  return not (file:find("/vendor/", 1, true) or file:match("^vendor/"))
end

-- the values of "Failed asserting that X matches expected Y." and alike: expected, actual
local COMPARISONS = {
  { "^Failed asserting that (.-) matches expected (.-)%.$", false },
  { "^Failed asserting that (.-) is identical to (.-)%.$", false },
  { "^Failed asserting that (.-) is equal to (.-)%.$", false },
}

--- Take a failure message apart.
---@param message string
---@param opts? { root?: string }
---@return { title?: string, lines: string[], diff?: string[], expected?: string, actual?: string, frames: { file: string, line: integer, project: boolean }[] }
function M.parse(message, opts)
  opts = opts or {}
  local all = split(message)
  local out = { lines = {}, frames = {} }
  local i = 1
  -- the first line names the test ("Class::method ..."), PHPUnit puts it before the message
  if all[1] and all[1]:match("^[%w_\\]+::[%w_]+") and not M.frame_of(all[1]) then
    out.title = all[1]
    i = 2
  end
  local diff, expected, actual
  while i <= #all do
    local line = all[i]
    local file, n = M.frame_of(line)
    if file then
      out.frames[#out.frames + 1] =
        { file = file, line = n, project = M.is_project_file(file, opts.root) }
    elseif line == "--- Expected" and all[i + 1] == "+++ Actual" and not diff then
      diff, expected, actual = { line, all[i + 1] }, {}, {}
      i = i + 2
      while i <= #all and all[i] ~= "" and not M.frame_of(all[i]) do
        local body = all[i]
        diff[#diff + 1] = body
        local mark, rest = body:sub(1, 1), body:sub(2)
        if mark == " " or mark == "-" then
          expected[#expected + 1] = rest
        end
        if mark == " " or mark == "+" then
          actual[#actual + 1] = rest
        end
        i = i + 1
      end
      i = i - 1
    elseif not (line == "" and (#out.lines == 0 or out.lines[#out.lines] == "")) then
      out.lines[#out.lines + 1] = line
    end
    i = i + 1
  end
  while #out.lines > 0 and out.lines[#out.lines] == "" do
    out.lines[#out.lines] = nil
  end
  if diff then
    out.diff = diff
    out.expected, out.actual = table.concat(expected, "\n"), table.concat(actual, "\n")
  else
    for _, line in ipairs(out.lines) do
      for _, c in ipairs(COMPARISONS) do
        local a, e = line:match(c[1])
        if a then
          out.actual, out.expected = a, e
          break
        end
      end
      if out.actual then
        break
      end
    end
  end
  return out
end

--- Where the failure comes from: the innermost frame of the project that is not the test file (an exception thrown
--- in the code under test), or nil.
function M.origin(parsed, test_file)
  for _, frame in ipairs(parsed.frames) do
    if frame.file == test_file then
      return nil -- it failed in the test itself
    end
    if frame.project then
      return frame
    end
  end
end

--- The line of the test file where it failed (1-based): the innermost frame in that file.
function M.test_line(parsed, test_file)
  for _, frame in ipairs(parsed.frames) do
    if frame.file == test_file then
      return frame.line
    end
  end
end

--- A duration for people: "4 ms", "1.3 s", "2 min 5 s".
function M.duration(seconds)
  seconds = tonumber(seconds)
  if not seconds then
    return nil
  end
  if seconds < 1 then
    return string.format("%d ms", math.floor(seconds * 1000 + 0.5))
  elseif seconds < 60 then
    return string.format("%.1f s", seconds)
  end
  return string.format("%d min %d s", math.floor(seconds / 60), math.floor(seconds % 60))
end

return M
