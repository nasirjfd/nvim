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
    -- the worker slot (TEST_THREAD_ID): two runs at the same time must never have the same one
    [[mkdir "$ROOT/slot-${TEST_THREAD_ID:-0}" 2>/dev/null || echo COLLISION >> "$ROOT/collisions.log"]],
    [[echo "${TEST_THREAD_ID:-none}" >> "$ROOT/slots.log"]],
    'ls "$ROOT/running" | wc -l | tr -d " " >> "$ROOT/concurrency.log"',
    "sleep 0.5",
    'rm "$ROOT/running/$$"',
    [[rmdir "$ROOT/slot-${TEST_THREAD_ID:-0}" 2>/dev/null]],
    -- no file given (a whole project): every class
    [[files="$file"; [ -z "$file" ] && files="$(ls "$ROOT"/app/tests/*Test.php | sed "s|^$ROOT|/ctr|")"]],
    [[echo "<testsuites>" > "$log"]],
    "for file in $files; do",
    [[  class="$(basename "$file" .php)"]],
    [[  failure=""]],
    [[  if [ -f "$ROOT/fail-${class%Test}" ]; then failure="$(printf '<failure type="X">%s::testTwo nope %s:9</failure>' "$class" "$file")"; fi]],
    -- testTwo is one test, or three data sets (#1 is the one that fails) when "sets-<Class>" exists
    [[  two_cases="$(printf '<testcase name="testTwo" class="%s" file="%s" line="8">%s</testcase>' "$class" "$file" "$failure")"]],
    [[  if [ -f "$ROOT/sets-${class%Test}" ]; then]],
    [[    two_cases=""]],
    [[    for n in 0 1 2; do]],
    [[      f=""; [ "$n" = 1 ] && f="$failure"]],
    [[      two_cases="$two_cases$(printf '<testcase name="testTwo with data set #%s" class="%s" file="%s" line="8">%s</testcase>' "$n" "$class" "$file" "$f")"]],
    "    done",
    "  fi",
    [[  printf '<testsuite name="%s" file="%s"><testcase name="testOne" class="%s" file="%s" line="4"/>%s</testsuite>\n' "$class" "$file" "$class" "$file" "$two_cases" >> "$log"]],
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
      command = "ROOT=" .. %q .. " ${env} " .. %q .. "/fake-phpunit.sh ${phpunitargs}",
      parallel_env = { TEST_THREAD_ID = "${slot}" },
      max_workers = vim.g.test_max_workers,
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
  lib.eq({ "none" }, lines(dir .. "/slots.log"), "a run that is not parallel has no worker slot (the project's default)")
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
  local slots = lines(dir .. "/slots.log")
  table.sort(slots)
  lib.eq(4, #slots)
  lib.ok(vim.tbl_contains({ "1", "2" }, slots[1]) and vim.tbl_contains({ "1", "2" }, slots[4]), "slots are 1..workers: " .. table.concat(slots, ","))
  lib.eq(0, #lines(dir .. "/collisions.log"), "two runs at the same time had the same worker slot")
  h.wait(screen, function()
    return counts(screen).passed == 8
  end, "all eight tests must have passed")
  screen:close()
end)

lib.test("tests run: a project's max_workers caps the workers, and slots stay within it", function()
  local dir = project()
  local screen = h.nvim(dir)
  screen:exec(string.format([[
    vim.g.test_max_workers = 3
    require("modules.phpunit").configure({
      root = %q, projects = { "app" }, paths = { [%q] = "/ctr" }, max_workers = 3,
      command = "ROOT=" .. %q .. " ${env} " .. %q .. "/fake-phpunit.sh ${phpunitargs}",
      parallel_env = { TEST_THREAD_ID = "${slot}" },
    })
    vim.cmd("edit " .. %q)
    local o = require("modules.phpunit.options")
    o.set_parallel(true)
  ]], dir, dir, dir, dir, dir .. "/app/tests/BTest.php"))
  lib.eq(3, screen:exec("return require('modules.phpunit.options').set_workers(50)"), "the number never goes above max_workers")
  lib.eq(3, screen:exec("return require('modules.phpunit.options').workers()"))
  screen:exec("require('modules.phpunit.pane').toggle()")
  h.wait(screen, function()
    return screen:exec("local p = require('modules.phpunit.pane'); return #(p.files_under(p.root_id() or '') or {}) == 4")
  end, "the four test files were not found")
  screen:exec("require('modules.phpunit.runner').run_all()")
  wait_runs(screen, dir, 4)
  lib.ok(max_concurrency(dir) <= 3, "more than max_workers at a time")
  for _, slot in ipairs(lines(dir .. "/slots.log")) do
    lib.ok(tonumber(slot) and tonumber(slot) >= 1 and tonumber(slot) <= 3, "slot out of range: " .. slot)
  end
  lib.eq(0, #lines(dir .. "/collisions.log"))
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

lib.test("tests run: the test under the cursor runs even before the pane has found the project's tests", function()
  local dir = project()
  local screen = start(dir)
  screen:exec("vim.cmd('wincmd l')")
  screen:exec("vim.api.nvim_win_set_cursor(0, { 9, 0 })")
  screen:exec("package.loaded['modules.phpunit.pane'].nearest = function() return nil end") -- as if it did not know the file
  screen:exec("require('modules.phpunit.runner').run_nearest()")
  wait_runs(screen, dir, 1)
  lib.matches("BTest%.php .*%-%-filter ::testTwo%(", lines(dir .. "/args.log")[1])
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

lib.test("tests pane: the failed tests come first, in a section above the folders", function()
  local dir = project()
  h.write(dir .. "/fail-B", { "x" })
  local screen = start(dir)
  h.wait(screen, function()
    return pane_row(screen, "Run all tests") ~= nil
  end, "no button")
  lib.ok(not pane_row(screen, "Failed"), "no Failed section before a run")
  h.click(screen, pane_row(screen, "Run all tests"), 8)
  h.wait(screen, function()
    return pane_row(screen, "✗ Failed") ~= nil
  end, "the Failed section did not appear", 20000)
  local failed_row = pane_row(screen, "✗ Failed")
  local files_row = pane_row(screen, "ATest.php")
  lib.ok(failed_row and files_row and failed_row < files_row, "Failed must be above the folders")
  local test_row = pane_row(screen, "testTwo")
  lib.ok(test_row and test_row > failed_row and test_row < files_row, "the failed test is listed in the section")
  lib.ok(pane_row(screen, "BTest.php") and pane_row(screen, "BTest.php") < files_row + 3, "with its file next to it")
  -- the section folds
  h.click(screen, failed_row, 8)
  h.wait(screen, function()
    return pane_row(screen, "testTwo") == nil
  end, "clicking the section did not fold it")
  screen:close()
end)

lib.test("tests pane: the Flat list button shows every test on its own row, failed ones first, and goes back", function()
  local dir = project()
  h.write(dir .. "/fail-C", { "x" })
  local screen = start(dir)
  h.wait(screen, function()
    return pane_row(screen, "Run all tests") ~= nil
  end, "no button")
  h.click(screen, pane_row(screen, "Run all tests"), 8)
  h.wait(screen, function()
    return pane_row(screen, "Run failed tests (1)") ~= nil
  end, "the run did not finish", 20000)
  h.click(screen, pane_row(screen, "Flat list"), 8)
  h.wait(screen, function()
    return pane_row(screen, "testOne") ~= nil
  end, "the flat list did not show the tests")
  lib.eq(true, screen:exec("return require('modules.phpunit.options').flat()"))
  lib.ok(not pane_row(screen, "✗ Failed"), "no separate section in the flat list")
  -- every test is there (8), the failed one first, each with its file
  local rows = 0
  for row = 1, 29 do
    local text = screen:text(row, 1, 54)
    if text:find("test%u") or text:find("test[OT]") then
      rows = rows + 1
    end
  end
  lib.eq(8, rows, "all eight tests listed")
  local first = pane_row(screen, "testTwo")
  lib.ok(first and pane_row(screen, "CTest.php") == first, "the failed test comes first with its file name")
  h.click(screen, pane_row(screen, "Flat list"), 8)
  h.wait(screen, function()
    return pane_row(screen, "ATest.php") ~= nil and pane_row(screen, "testOne") == nil
  end, "the button did not bring the folders back")
  lib.eq(false, screen:exec("return require('modules.phpunit.options').flat()"))
  screen:close()
end)

lib.test("tests pane: the buttons at the top are quiet (dark tints, nothing bold)", function()
  local screen = h.nvim(h.tmpdir())
  screen:exec("require('modules.phpunit.pane')") -- defines the highlights
  local groups = { "PhpTestToggleOn", "PhpTestToggleOff", "PhpTestStepOn", "PhpTestStepOff", "PhpTestRun", "PhpTestRunFailed", "PhpTestRunIdle" }
  for _, name in ipairs(groups) do
    local hl = screen:exec("return vim.api.nvim_get_hl(0, { name = ... })", { name })
    lib.ok(not hl.bold, name .. " must not be bold")
    local r, g, b = math.floor(hl.bg / 65536) % 256, math.floor(hl.bg / 256) % 256, hl.bg % 256
    lib.ok(math.max(r, g, b) <= 0x56, name .. " background is too bright: " .. string.format("#%02x%02x%02x", r, g, b))
  end
  screen:close()
end)

-- ── the failure message ─────────────────────────────────────────────────────────────────────────
lib.test("tests messages: a failed test's message is shown under the failing line, not as a diagnostic at its end", function()
  local dir = project()
  h.write(dir .. "/fail-B", { "x" })
  local screen = start(dir)
  local function marks()
    return screen:exec([[
      local ns = require("modules.phpunit.messages").namespace
      local out = {}
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
        out[#out + 1] = { row = m[2], lines = #(m[4].virt_lines or {}), sign = m[4].sign_text }
      end
      return out
    ]])
  end
  screen:exec("vim.cmd('wincmd l')") -- BTest.php is open in the editor window
  screen:exec("require('modules.phpunit.runner').run_all()")
  h.wait(screen, function()
    return #marks() == 1
  end, "no message appeared under the failing line", 20000)
  local mark = marks()[1]
  lib.eq(8, mark.row, "under the line the failure points at (PHPUnit says BTest.php:9, 0-based 8)")
  lib.ok(mark.lines >= 1, "the message is virtual lines below the line")
  lib.matches("󰅚", mark.sign, "an error sign in the gutter")
  lib.eq(0, screen:exec([[
    local ns = vim.api.nvim_get_namespaces().neotest
    return ns and #vim.diagnostic.get(0, { namespace = ns }) or 0
  ]]), "neotest's own diagnostic is off (tiny-inline-diagnostic would draw it at the end of the line)")
  -- the message is on the screen, under line 9 (row of line 10)
  h.wait(screen, function()
    return h.find_on_screen(screen, "BTest::testTwo", 200) ~= nil
  end, "the message is not on the screen")
  -- it goes when the test passes
  vim.fn.delete(dir .. "/fail-B")
  screen:exec("require('modules.phpunit.runner').run_all()")
  h.wait(screen, function()
    return #marks() == 0
  end, "the message stayed after the test passed", 20000)
  screen:close()
end)

lib.test("tests messages: the message is the test name, the error and no stack trace", function()
  local screen = h.nvim(h.tmpdir())
  local lines = screen:exec([[
    local text = "FooTest::testIt\nError: Call to a member function x() on null\n\n/var/www/Foo.php:12\n/var/www/Bar.php:99"
    local out = {}
    for _, line in ipairs(require("modules.phpunit.messages").format(text)) do
      local joined = ""
      for _, chunk in ipairs(line) do joined = joined .. chunk[1] end
      out[#out + 1] = joined
    end
    return out
  ]])
  lib.eq({ " ● FooTest::testIt", " └ Error: Call to a member function x() on null" }, lines)
  screen:close()
end)

-- ── memory between sessions ─────────────────────────────────────────────────────────────────────
package.path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h") .. "/lua/?.lua;" .. package.path

lib.test("tests memory: results are kept per project, messages shortened, tests of deleted files forgotten", function()
  local memory = require("modules.phpunit.memory")
  local dir = h.tmpdir()
  memory.set_file(dir .. "/results.json")
  h.write(dir .. "/ATest.php", { "x" })
  local file = dir .. "/ATest.php"
  local long = string.rep("x", 5000)
  memory.remember("/root", {
    [file .. "::testA"] = { status = "passed", output = "/tmp/out" },
    [file .. "::testB"] = { status = "failed", short = "boom", errors = { { line = 3, message = long } } },
    [file .. "::testC"] = { status = "skipped" },
    [file .. "::testE"] = { status = "failed", short = "x", errors = {}, datasets = { { label = "#0", status = "passed" }, { label = "#1", status = "failed", short = "bad" } } },
    [file] = { status = "failed" }, -- a file, not a test
    [dir .. "/gone/BTest.php::testD"] = { status = "failed" }, -- its file does not exist
  }, function(id)
    return id:find("::", 1, true) ~= nil
  end)
  memory.set_file(dir .. "/results.json") -- a new session reads the file
  local back = memory.recall("/root")
  lib.eq({ status = "passed" }, back[file .. "::testA"], "nothing but the status of a passed test")
  lib.eq("failed", back[file .. "::testB"].status)
  lib.eq(3, back[file .. "::testB"].errors[1].line)
  lib.ok(#back[file .. "::testB"].errors[1].message < 2000, "a long message is cut")
  lib.eq("skipped", back[file .. "::testC"].status)
  lib.eq(2, #back[file .. "::testE"].datasets, "the data sets are kept")
  lib.eq({ "#1", "failed" }, { back[file .. "::testE"].datasets[2].label, back[file .. "::testE"].datasets[2].status })
  lib.eq(nil, back[file], "a file is not a test")
  lib.eq(nil, back[dir .. "/gone/BTest.php::testD"], "a test of a deleted file is forgotten")
  lib.eq({}, memory.recall("/other/project"), "another project has its own")
  -- what is not in a later run stays
  memory.remember("/root", { [file .. "::testA"] = { status = "failed", short = "now", errors = {} } }, function()
    return true
  end)
  local again = memory.recall("/root")
  lib.eq("failed", again[file .. "::testA"].status)
  lib.eq("failed", again[file .. "::testB"].status, "the other results are still there")
end)

lib.test("tests memory: after a restart the failed tests are still known and only they run again", function()
  local dir = project()
  h.write(dir .. "/fail-B", { "x" })
  local memory_file = dir .. "/remembered.json"
  local function session()
    local screen = h.nvim(dir)
    screen:exec(string.format("require('modules.phpunit.memory').set_file(%q)", memory_file))
    return screen
  end
  -- first session: run everything, one test fails
  local first = session()
  first:exec(string.format([[
    require("modules.phpunit").configure({
      root = %q, projects = { "app" }, paths = { [%q] = "/ctr" },
      command = "ROOT=" .. %q .. " ${env} " .. %q .. "/fake-phpunit.sh ${phpunitargs}",
    })
    vim.cmd("edit " .. %q)
    require("modules.phpunit.pane").toggle()
  ]], dir, dir, dir, dir, dir .. "/app/tests/BTest.php"))
  h.wait(first, function()
    return first:exec("local p = require('modules.phpunit.pane'); return #(p.files_under(p.root_id() or '') or {}) == 4")
  end, "the files were not found")
  first:exec("require('modules.phpunit.runner').run_all()")
  h.wait(first, function()
    local c = counts(first)
    return c.passed == 7 and c.failed == 1 and c.running == 0
  end, "the run did not give 7 passed and 1 failed", 20000)
  vim.wait(1200) -- the results are saved a moment after they come in
  first:close()
  lib.ok(vim.fn.filereadable(memory_file) == 1, "nothing was remembered")
  vim.fn.delete(dir .. "/args.log")
  vim.fn.delete(dir .. "/fail-B") -- it would pass now, if it ran

  -- second session: nothing has run, yet the pane knows
  local second = session()
  second:exec(string.format([[
    require("modules.phpunit").configure({
      root = %q, projects = { "app" }, paths = { [%q] = "/ctr" },
      command = "ROOT=" .. %q .. " ${env} " .. %q .. "/fake-phpunit.sh ${phpunitargs}",
    })
    vim.cmd("edit " .. %q)
    require("modules.phpunit.pane").toggle()
  ]], dir, dir, dir, dir, dir .. "/app/tests/BTest.php"))
  h.wait(second, function()
    return h.find_on_screen(second, "Run failed tests (1)", 54) ~= nil and h.find_on_screen(second, "✓ 7", 54) ~= nil
  end, "the pane does not remember 7 passed and 1 failed", 20000)
  lib.eq(0, #lines(dir .. "/args.log"), "remembering must not run anything")
  -- and its message is under the line again
  second:exec("vim.cmd('wincmd l')")
  h.wait(second, function()
    return #second:exec("return vim.api.nvim_buf_get_extmarks(0, require('modules.phpunit.messages').namespace, 0, -1, {})") == 1
  end, "the failure message did not come back")
  second:exec("require('modules.phpunit.runner').run_failed()")
  wait_runs(second, dir, 1)
  vim.wait(500)
  local runs = lines(dir .. "/args.log")
  lib.eq(1, #runs, "only the failed test's file runs")
  lib.matches("BTest%.php .*%-%-filter ::testTwo%(", runs[1])
  second:close()
end)

-- ── data sets ───────────────────────────────────────────────────────────────────────────────────
lib.test("tests data sets: every data set counts and is listed on its own, the failed one in the Failed section", function()
  local dir = project()
  h.write(dir .. "/sets-A", { "x" })
  h.write(dir .. "/fail-A", { "x" })
  local screen = start(dir)
  h.wait(screen, function()
    return h.find_on_screen(screen, "8 tests", 54) ~= nil
  end, "before a run every method counts once: 8")
  screen:exec("require('modules.phpunit.runner').run_all()")
  h.wait(screen, function()
    return h.find_on_screen(screen, "10 tests", 54) ~= nil and h.find_on_screen(screen, "✓ 9", 54) ~= nil and h.find_on_screen(screen, "✗ 1", 54) ~= nil
  end, "the header must count 10 runs: 9 passed, 1 failed", 20000)
  -- the Failed section lists the data set that failed, not the method
  local failed_row = h.find_on_screen(screen, "✗ Failed", 54)
  local set_row = h.find_on_screen(screen, "#1", 54)
  lib.ok(failed_row and set_row and set_row == failed_row + 1, "the failed data set #1 is the row under Failed")
  lib.ok(not h.find_on_screen(screen, "#0", 54), "the passing data sets are not in the Failed section")
  -- in the tree the method says how many it has and unfolds
  -- the file's own row (the failed data set shows the file name too)
  local row
  for r = 1, 29 do
    local text = screen:text(r, 1, 54)
    if text:find("ATest.php", 1, true) and not text:find("test", 1, true) then
      row = r
    end
  end
  lib.ok(row, "the file is in the tree")
  h.click(screen, row, 8)
  h.wait(screen, function()
    return h.find_on_screen(screen, "×3", 54) ~= nil
  end, "the method must show ×3")
  h.click(screen, h.find_on_screen(screen, "×3", 54), 8)
  h.wait(screen, function()
    return h.find_on_screen(screen, "with data set #0", 54) ~= nil and h.find_on_screen(screen, "with data set #2", 54) ~= nil
  end, "clicking the method did not show its data sets")
  screen:close()
end)

lib.test("tests data sets: Run failed runs only the failed data set, the Flat list shows each one", function()
  local dir = project()
  h.write(dir .. "/sets-A", { "x" })
  h.write(dir .. "/fail-A", { "x" })
  local screen = start(dir)
  screen:exec("require('modules.phpunit.runner').run_all()")
  h.wait(screen, function()
    return h.find_on_screen(screen, "10 tests", 54) ~= nil and h.find_on_screen(screen, "Run failed tests (1)", 54) ~= nil
  end, "the run did not finish", 20000)
  vim.fn.delete(dir .. "/args.log")
  screen:exec("require('modules.phpunit.runner').run_failed()")
  wait_runs(screen, dir, 1)
  local run = lines(dir .. "/args.log")[1]
  lib.matches("ATest%.php .*%-%-filter ::testTwo with data set #1%$", run)
  -- flat: testTwo three times, #0 #1 #2
  screen:exec("require('modules.phpunit.options').set_flat(true)")
  screen:exec("require('modules.phpunit.pane').panes()[1]:find()")
  h.wait(screen, function()
    return h.find_on_screen(screen, "testTwo #0", 54) ~= nil and h.find_on_screen(screen, "testTwo #1", 54) ~= nil and h.find_on_screen(screen, "testTwo #2", 54) ~= nil
  end, "the flat list must show each data set")
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
