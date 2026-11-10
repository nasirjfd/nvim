-- Running tests from the pane and the keys: all, a file, the one under the cursor, only what failed, the last run
-- again, and several files at once (the Parallel option). A fake phpunit stands in for the Docker container: it
-- records how many instances run at the same moment.
local lib = require("lib")
local h = require("support")

local CLASSES = { "A", "B", "C", "D" }

local function project()
  local dir = vim.fn.resolve(h.tmpdir())
  h.write(dir .. "/app/tests.xml", { "<phpunit/>" })
  for _, name in ipairs(CLASSES) do
    h.write(dir .. "/app/tests/" .. name .. "Test.php", {
      "<?php",
      "class " .. name .. "Test extends \\PHPUnit\\Framework\\TestCase",
      "{",
      "    public function testOne()",
      "    {",
      "    }",
      "",
      "    public function testTwo()",
      "    {",
      "    }",
      "}",
    })
  end
  -- the fake: a class whose marker file "fail-<Class>" exists fails testTwo; every run takes half a second
  h.write(dir .. "/fake-phpunit.sh", {
    "#!/bin/sh",
    'echo "$@" >> "$ROOT/args.log"',
    'for a in "$@"; do',
    '  case "$a" in',
    '    --log-junit=*) log="${a#--log-junit=}";;',
    '    *Test.php) file="$a";;',
    "  esac",
    "done",
    'log="$ROOT${log#/ctr}"',
    'mkdir -p "$ROOT/running" "$(dirname "$log")"',
    'touch "$ROOT/running/$$"',
    'ls "$ROOT/running" | wc -l | tr -d " " >> "$ROOT/concurrency.log"',
    "sleep 0.5",
    'rm "$ROOT/running/$$"',
    -- no file given (a whole project): every class
    [[files="$file"; [ -z "$file" ] && files="$(ls "$ROOT"/app/tests/*Test.php | sed "s|^$ROOT|/ctr|")"]],
    [[echo "<testsuites>" > "$log"]],
    "for file in $files; do",
    [[  class="$(basename "$file" .php)"]],
    [[  two=""]],
    [[  if [ -f "$ROOT/fail-${class%Test}" ]; then two="$(printf '<failure type="X">%s::testTwo nope %s:9</failure>' "$class" "$file")"; fi]],
    [[  printf '<testsuite name="%s" file="%s"><testcase name="testOne" class="%s" file="%s" line="4"/><testcase name="testTwo" class="%s" file="%s" line="8">%s</testcase></testsuite>\n' "$class" "$file" "$class" "$file" "$class" "$file" "$two" >> "$log"]],
    "done",
    [[echo "</testsuites>" >> "$log"]],
    "exit 0",
  })
  vim.fn.system({ "chmod", "+x", dir .. "/fake-phpunit.sh" })
  return dir
end

local function start(dir)
  local screen = h.nvim(dir)
  screen:exec(
    string.format(
      [[
    require("modules.phpunit").configure({
      root = %q, projects = { "app" }, paths = { [%q] = "/ctr" },
      command = "ROOT=" .. %q .. " " .. %q .. "/fake-phpunit.sh ${phpunitargs}",
    })
    vim.cmd("edit " .. %q)
    require("modules.phpunit.options").set_parallel(false)
    require("modules.phpunit.pane").toggle()
  ]],
      dir, dir, dir, dir, dir .. "/app/tests/BTest.php"
    )
  )
  h.wait(screen, function()
    return screen:exec("local p = require('modules.phpunit.pane'); return #(p.files_under(p.root_id() or '') or {}) == 4")
  end, "the four test files were not found")
  return screen
end

local function lines(path)
  return vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
end

local function counts(screen)
  return screen:exec([[
    local ids = require("neotest").state.adapter_ids()
    return ids[1] and require("neotest").state.status_counts(ids[1]) or {}
  ]])
end

local function max_concurrency(dir)
  local most = 0
  for _, line in ipairs(lines(dir .. "/concurrency.log")) do
    most = math.max(most, tonumber(line) or 0)
  end
  return most
end

local function wait_runs(screen, dir, n, what)
  h.wait(screen, function()
    return #lines(dir .. "/args.log") >= n and counts(screen).running == 0
  end, what or ("phpunit did not run " .. n .. " times"), 20000)
end

lib.test("tests run: all tests one after the other when Parallel is off (one phpunit per project)", function()
  local dir = project()
  local screen = start(dir)
  screen:exec("require('modules.phpunit.runner').run_all()")
  wait_runs(screen, dir, 1)
  vim.wait(800)
  lib.eq(1, #lines(dir .. "/args.log"), "a project is run as a whole")
  lib.eq(1, max_concurrency(dir))
  h.wait(screen, function()
    return counts(screen).passed == 8
  end, "all eight tests must have passed")
  screen:close()
end)

lib.test("tests run: with Parallel on every file is its own phpunit, `workers` at a time", function()
  local dir = project()
  local screen = start(dir)
  screen:exec("local o = require('modules.phpunit.options'); o.set_parallel(true); o.set_workers(2)")
  screen:exec("require('modules.phpunit.runner').run_all()")
  wait_runs(screen, dir, 4)
  lib.eq(4, #lines(dir .. "/args.log"), "one phpunit per file")
  lib.eq(2, max_concurrency(dir), "two at a time, not more and not fewer")
  h.wait(screen, function()
    return counts(screen).passed == 8
  end, "all eight tests must have passed")
  screen:close()
end)

lib.test("tests run: only the failed tests run again, by name, in their files", function()
  local dir = project()
  h.write(dir .. "/fail-A", { "x" })
  h.write(dir .. "/fail-C", { "x" })
  local screen = start(dir)
  screen:exec("require('modules.phpunit.runner').run_all()")
  h.wait(screen, function()
    return counts(screen).failed == 2 and counts(screen).running == 0
  end, "A and C must have one failure each", 20000)
  vim.fn.delete(dir .. "/args.log")
  screen:exec("require('modules.phpunit.runner').run_failed()")
  wait_runs(screen, dir, 2)
  vim.wait(500)
  local runs = lines(dir .. "/args.log")
  lib.eq(2, #runs)
  table.sort(runs)
  lib.matches("ATest%.php .*%-%-filter ::testTwo%(", runs[1])
  lib.matches("CTest%.php .*%-%-filter ::testTwo%(", runs[2])
  screen:close()
end)

lib.test("tests run: nothing to run when nothing failed", function()
  local dir = project()
  local screen = start(dir)
  screen:exec("_G.notes = {}; vim.notify = function(m) table.insert(_G.notes, m) end")
  screen:exec("require('modules.phpunit.runner').run_failed()")
  h.wait(screen, function()
    return #screen:exec("return _G.notes") == 1
  end, "no message")
  lib.matches("No failed tests", screen:exec("return _G.notes[1]"))
  lib.eq(0, #lines(dir .. "/args.log"))
  screen:close()
end)

lib.test("tests run: the test under the cursor, the file, and the last run again", function()
  local dir = project()
  local screen = start(dir)
  screen:exec("vim.cmd('wincmd l')") -- the editor, not the pane
  screen:exec("vim.api.nvim_win_set_cursor(0, { 9, 0 })") -- inside testTwo of BTest.php
  screen:exec("require('modules.phpunit.runner').run_nearest()")
  wait_runs(screen, dir, 1)
  lib.matches("BTest%.php .*%-%-filter ::testTwo%(", lines(dir .. "/args.log")[1])
  screen:exec("vim.api.nvim_win_set_cursor(0, { 1, 0 })") -- above every test: the first one above does not exist
  screen:exec("require('modules.phpunit.runner').run_file()")
  wait_runs(screen, dir, 2)
  lib.matches("BTest%.php %-%-log", lines(dir .. "/args.log")[2])
  screen:exec("require('modules.phpunit.runner').run_last()")
  wait_runs(screen, dir, 3)
  lib.matches("BTest%.php %-%-log", lines(dir .. "/args.log")[3])
  screen:close()
end)

lib.test("tests run: stopping ends the queue of a parallel run", function()
  local dir = project()
  local screen = start(dir)
  screen:exec("local o = require('modules.phpunit.options'); o.set_parallel(true); o.set_workers(2)")
  screen:exec("require('modules.phpunit.runner').run_all()")
  h.wait(screen, function()
    return #lines(dir .. "/args.log") >= 2
  end, "the first two did not start")
  screen:exec("require('modules.phpunit.runner').stop()")
  vim.wait(1500)
  lib.ok(#lines(dir .. "/args.log") < 4, "the files waiting for a worker must not start after stop")
  screen:close()
end)

lib.test("tests options: up to 64 workers, the + and - keys step by 5 above 10, the choice is kept", function()
  local screen = h.nvim(h.tmpdir())
  lib.eq(50, screen:exec("local o = require('modules.phpunit.options'); return o.set_workers(50)"))
  lib.eq(64, screen:exec("return require('modules.phpunit.options').set_workers(500)"), "the top is 64")
  lib.eq(2, screen:exec("return require('modules.phpunit.options').set_workers(0)"), "the bottom is 2")
  screen:exec("local o = require('modules.phpunit.options'); o.set_workers(8)")
  lib.eq({ 1, 5, 5, 1 }, screen:exec([[
    local o = require('modules.phpunit.options')
    local out = {}
    o.set_workers(9); out[1] = o.step(true)
    o.set_workers(10); out[2] = o.step(true)
    o.set_workers(15); out[3] = o.step(false)
    o.set_workers(10); out[4] = o.step(false)
    return out
  ]]))
  screen:exec("require('modules.phpunit.options').set_workers(50); require('modules.phpunit.options').reload()")
  lib.eq(50, screen:exec("return require('modules.phpunit.options').workers()"), "kept")
  screen:close()
end)

-- ── the pane ────────────────────────────────────────────────────────────────────────────────────
local function pane_row(screen, text)
  local row, col = h.find_on_screen(screen, text, 54)
  return row, col
end

lib.test("tests pane: counts and checkbox on top, then the parent folder, the file and every test", function()
  local dir = project()
  local screen = start(dir)
  h.wait(screen, function()
    return pane_row(screen, "ATest.php") ~= nil
  end, "the test files are not in the pane")
  lib.ok(pane_row(screen, "Parallel"), "the Parallel checkbox")
  lib.ok(pane_row(screen, "Run all tests"), "Run all")
  lib.ok(pane_row(screen, "Run failed tests"), "Run failed")
  lib.ok(pane_row(screen, "8 tests"), "the count")
  lib.ok(pane_row(screen, "tests") and pane_row(screen, "app"), "the parent folder with its project")
  lib.ok(not pane_row(screen, "testOne"), "tests are folded under their file at first")
  h.click(screen, pane_row(screen, "ATest.php"), 8)
  h.wait(screen, function()
    return pane_row(screen, "testOne") ~= nil and pane_row(screen, "testTwo") ~= nil
  end, "clicking the file did not show its tests")
  screen:close()
end)

lib.test("tests pane: the Parallel row is a checkbox with a clickable number: - 4 + at a time", function()
  local dir = project()
  local screen = start(dir)
  h.wait(screen, function()
    return pane_row(screen, "at a time") ~= nil
  end, "no Parallel row")
  local function workers()
    return screen:exec("return require('modules.phpunit.options').workers()")
  end
  local function parallel()
    return screen:exec("return require('modules.phpunit.options').parallel()")
  end
  local row, plus = pane_row(screen, "+")
  local _, minus = pane_row(screen, "−")
  lib.ok(row and minus and minus < plus, "− and + buttons are on the row")
  lib.eq(false, parallel())
  h.click(screen, row, plus)
  h.wait(screen, function()
    return workers() == 5
  end, "clicking + did not raise the number")
  h.click(screen, row, minus)
  h.click(screen, row, minus)
  h.wait(screen, function()
    return workers() == 3
  end, "clicking − twice did not lower the number")
  lib.eq(false, parallel(), "the buttons do not toggle Parallel")
  h.click(screen, row, 6) -- the checkbox
  h.wait(screen, parallel, "the checkbox did not turn Parallel on")
  h.wait(screen, function()
    return pane_row(screen, " 3 ") ~= nil
  end, "the row does not show the number")
  -- above ten the buttons step by five; the keys do the same
  screen:exec("require('modules.phpunit.options').set_workers(10)")
  screen:exec("require('modules.phpunit.pane').panes()[1]:find()")
  h.wait(screen, function()
    return pane_row(screen, " 10 ") ~= nil
  end, "no 10")
  row, plus = pane_row(screen, "+")
  h.click(screen, row, plus)
  h.wait(screen, function()
    return workers() == 15
  end, "+ above ten must step by five")
  for _, key in ipairs({ "+", "=" }) do
    screen:input(key)
  end
  h.wait(screen, function()
    return workers() == 25
  end, "the + and = keys must step too")
  screen:input("-")
  h.wait(screen, function()
    return workers() == 20
  end, "the - key must step down")
  screen:exec("require('modules.phpunit.options').reload()")
  lib.eq(20, workers(), "the choice is kept")
  screen:close()
end)

lib.test("tests pane: results show next to the tests and a click on Run all runs them", function()
  local dir = project()
  h.write(dir .. "/fail-B", { "x" })
  local screen = start(dir)
  h.wait(screen, function()
    return pane_row(screen, "Run all tests") ~= nil
  end, "no button")
  h.click(screen, pane_row(screen, "Run all tests"), 8)
  h.wait(screen, function()
    return pane_row(screen, "✓ 7") ~= nil and pane_row(screen, "✗ 1") ~= nil and pane_row(screen, "Run failed tests (1)") ~= nil
  end, "the counts did not show 7 passed and 1 failed", 20000)
  screen:close()
end)

lib.test("tests pane: the terminal cursor is hidden in it", function()
  local screen = start(project())
  h.wait(screen, function()
    return screen:exec("return require('modules.pane_kit').hidden()")
  end, "the cursor must be hidden in the tests pane")
  screen:close()
end)

lib.test("tests pane: it replaces the Explorer and the HTTP pane, one sidebar at a time", function()
  local dir = project()
  local screen = start(dir)
  local function state()
    return screen:exec([[
      return { tests = #require("modules.phpunit.pane").panes(), http = #require("modules.http_requests").panes(),
        explorers = #Snacks.picker.get({ source = "explorer" }), cmdheight = vim.o.cmdheight }
    ]])
  end
  lib.eq({ tests = 1, http = 0, explorers = 0, cmdheight = 1 }, state())
  screen:exec("vim.fn.maparg('<leader>h', 'n', false, true).callback()")
  h.wait(screen, function()
    local s = state()
    return s.tests == 0 and s.http == 1
  end, "the HTTP pane must replace the tests pane")
  screen:exec("vim.fn.maparg('<D-S-t>', 'n', false, true).callback()")
  h.wait(screen, function()
    local s = state()
    return s.tests == 1 and s.http == 0 and s.cmdheight == 1
  end, "the tests pane must replace the HTTP pane")
  screen:exec("vim.fn.maparg('<D-S-e>', 'n', false, true).callback()")
  h.wait(screen, function()
    local s = state()
    return s.tests == 0 and s.explorers == 1 and s.cmdheight == 1
  end, "the Explorer must replace the tests pane")
  screen:close()
end)

-- ── smoothness ──────────────────────────────────────────────────────────────────────────────────
-- Every redraw of the screen is a frame the eye can see. A refresh used to put the list on its first row for a
-- moment and back again (a flash); the rows of the pane must not move at all when a folder is folded.
lib.test("tests pane: folding, unfolding and refreshing do not flash (the list never jumps)", function()
  local dir = vim.fn.resolve(h.tmpdir())
  h.write(dir .. "/app/tests.xml", { "<phpunit/>" })
  for i = 1, 40 do
    local name = string.format("D%02d", i)
    h.write(dir .. "/app/tests/" .. name .. "/" .. name .. "Test.php", {
      "<?php", "class " .. name .. "Test extends \\PHPUnit\\Framework\\TestCase", "{", "    public function testOne()", "    {", "    }", "}",
    })
  end
  local screen = h.nvim(dir, 120, 30)
  screen:exec(string.format([[
    require("modules.phpunit").configure({ root = %q, projects = { "app" }, command = "true" })
    require("modules.phpunit.pane").toggle()
  ]], dir))
  h.wait(screen, function()
    return screen:exec("local p = require('modules.phpunit.pane'); return #(p.files_under(p.root_id() or '') or {}) == 40")
  end, "the 40 test files were not found")
  vim.wait(600)
  screen:exec("require('modules.phpunit.pane').panes()[1].list:move(40, true)") -- far down the list
  vim.wait(400)
  local frames = {}
  screen.on_flush = function()
    local rows = {}
    for row = 1, 29 do
      rows[#rows + 1] = screen:text(row, 1, 54)
    end
    frames[#frames + 1] = rows
  end
  local function tops_during(keys)
    frames = {}
    if keys then
      screen:input(keys)
    else
      screen:exec("require('modules.phpunit.pane').panes()[1]:find()")
    end
    vim.wait(600)
    local seen, count = {}, 0
    for _, rows in ipairs(frames) do
      local row = rows[5]
      if not seen[row] then
        seen[row] = true
        count = count + 1
      end
    end
    return count, #frames
  end
  for _, keys in ipairs({ "<CR>", "<CR>", "h", "l" }) do
    local distinct, n = tops_during(keys)
    lib.ok(n >= 1, "no frame after " .. keys)
    lib.eq(1, distinct, "the list jumped while handling " .. keys .. " (" .. distinct .. " different tops in " .. n .. " frames)")
  end
  local distinct = tops_during(nil)
  lib.ok(distinct <= 1, "a plain refresh made the list jump")
  screen:close()
end)
