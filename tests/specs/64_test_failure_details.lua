-- The failure view of a test (lua/modules/phpunit/details.lua, failure.lua): the message, the expected/actual
-- comparison, the stack trace as links, the output, how long it took; ]f / [f from failure to failure,
-- <leader>td, <leader>tq, the mark where an exception was thrown, the comparison side by side.
-- The junit log is the one real PHPUnit 9 (supernova's) writes, only its paths are the fake container's.
local lib = require("lib")
local h = require("support")

package.path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h") .. "/lua/?.lua;" .. package.path
local failure = require("modules.phpunit.failure")

-- ── taking a message apart (pure) ───────────────────────────────────────────────────────────────
lib.test("test failure: a comparison gives the diff and the two values, the trace its frames", function()
  local p = failure.parse(table.concat({
    "XTest::testSame",
    "Failed asserting that two strings are identical.",
    "--- Expected",
    "+++ Actual",
    "@@ @@",
    " 'a",
    "-b'",
    "+c'",
    "",
    "/r/app/tests/XTest.php:6",
  }, "\n"), { root = "/r" })
  lib.eq("XTest::testSame", p.title)
  lib.eq({ "Failed asserting that two strings are identical." }, p.lines)
  lib.eq("'a\nb'", p.expected)
  lib.eq("'a\nc'", p.actual)
  lib.eq(6, #p.diff)
  lib.eq({ { file = "/r/app/tests/XTest.php", line = 6, project = true } }, p.frames)
  lib.eq(6, failure.test_line(p, "/r/app/tests/XTest.php"))
  lib.eq(nil, failure.origin(p, "/r/app/tests/XTest.php"), "it failed in the test itself")
end)

lib.test("test failure: an exception from the code under test has its origin; dependencies are not the project", function()
  local p = failure.parse(table.concat({
    "XTest::testErr",
    "RuntimeException: boom",
    "",
    "/r/vendor/lib/Helper.php:7",
    "/r/app/src/Thrower.php:6",
    "/r/app/tests/XTest.php:15",
    "",
    "Caused by",
    "LogicException: inner",
    "",
    "/r/app/src/Inner.php:3",
  }, "\n"), { root = "/r" })
  lib.eq({ "RuntimeException: boom", "", "Caused by", "LogicException: inner" }, p.lines)
  lib.eq(false, p.frames[1].project, "vendor is a dependency")
  lib.eq({ file = "/r/app/src/Thrower.php", line = 6, project = true }, failure.origin(p, "/r/app/tests/XTest.php"))
  lib.eq(15, failure.test_line(p, "/r/app/tests/XTest.php"))
  lib.eq(4, #p.frames)
end)

lib.test("test failure: scalar comparisons without a diff, durations", function()
  local p = failure.parse("XTest::testEq\nFailed asserting that 2 matches expected 1.\n\n/r/t/XTest.php:10")
  lib.eq({ "1", "2" }, { p.expected, p.actual })
  local q = failure.parse("Failed asserting that 3 is identical to 4.")
  lib.eq({ "4", "3" }, { q.expected, q.actual })
  lib.eq(nil, failure.parse("Failed asserting that false is true.").expected)
  lib.eq("0 ms", failure.duration(0.0002))
  lib.eq("12 ms", failure.duration(0.012))
  lib.eq("1.5 s", failure.duration(1.5))
  lib.eq("2 min 5 s", failure.duration(125))
end)

-- ── a run ───────────────────────────────────────────────────────────────────────────────────────
local TEST = {
  "<?php", -- 1
  "class XTest extends \\PHPUnit\\Framework\\TestCase",
  "{",
  "    public function testSame()", -- 4
  "    {",
  '        $this->assertSame("a\\nb", "a\\nc");', -- 6
  "    }",
  "    public function testEq()", -- 8
  "    {",
  "        $this->assertEquals(1, 2);", -- 10
  "    }",
  "    public function testErr()", -- 12
  "    {",
  '        echo "hello out\\n";',
  "        (new Thrower())->go();", -- 15
  "    }",
  "    /** @dataProvider p */",
  "    public function testSets($x)", -- 18
  "    {",
  "        $this->assertTrue($x);", -- 20
  "    }",
  "    public function p() { return ['ok' => [true], 'bad' => [false]]; }",
  "    public function testSkip()", -- 23
  "    {",
  "        $this->markTestSkipped('later');",
  "    }",
  "}",
}

local THROWER = {
  "<?php",
  "class Thrower",
  "{",
  "    public function go()",
  "    {",
  '        throw new \\RuntimeException("boom <&> \\"q\\"");', -- 6
  "    }",
  "}",
}

-- what PHPUnit 9.6 wrote for these tests (paths: the container's)
local JUNIT = [[<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="XTest" file="/ctr/app/tests/XTest.php" tests="6" assertions="4" errors="1" warnings="0" failures="3" skipped="1" time="1.204100">
    <testcase name="testSame" class="XTest" classname="XTest" file="/ctr/app/tests/XTest.php" line="4" assertions="1" time="0.002907">
      <failure type="PHPUnit\Framework\ExpectationFailedException">XTest::testSame
Failed asserting that two strings are identical.
--- Expected
+++ Actual
@@ @@
 'a
-b'
+c'

/ctr/app/tests/XTest.php:6</failure>
    </testcase>
    <testcase name="testEq" class="XTest" classname="XTest" file="/ctr/app/tests/XTest.php" line="8" assertions="1" time="1.200194">
      <failure type="PHPUnit\Framework\ExpectationFailedException">XTest::testEq
Failed asserting that 2 matches expected 1.

/ctr/app/tests/XTest.php:10</failure>
    </testcase>
    <testcase name="testErr" class="XTest" classname="XTest" file="/ctr/app/tests/XTest.php" line="12" assertions="0" time="0.000361">
      <error type="RuntimeException">XTest::testErr
RuntimeException: boom &lt;&amp;&gt; "q"

/ctr/app/src/Thrower.php:6
/ctr/app/tests/XTest.php:15</error>
      <system-out>hello out
</system-out>
    </testcase>
    <testsuite name="XTest::testSets" tests="2" assertions="2" errors="0" warnings="0" failures="1" skipped="0" time="0.000280">
      <testcase name="testSets with data set &quot;ok&quot;" class="XTest" classname="XTest" file="/ctr/app/tests/XTest.php" line="18" assertions="1" time="0.000250"/>
      <testcase name="testSets with data set &quot;bad&quot;" class="XTest" classname="XTest" file="/ctr/app/tests/XTest.php" line="18" assertions="1" time="0.000030">
        <failure type="PHPUnit\Framework\ExpectationFailedException">XTest::testSets with data set "bad" (false)
Failed asserting that false is true.

/ctr/app/tests/XTest.php:20</failure>
      </testcase>
    </testsuite>
    <testcase name="testSkip" class="XTest" classname="XTest" file="/ctr/app/tests/XTest.php" line="23" assertions="0" time="0.000358">
      <skipped/>
    </testcase>
  </testsuite>
</testsuites>]]

local function project()
  local dir = vim.fn.resolve(h.tmpdir())
  h.write(dir .. "/app/tests.xml", { "<phpunit/>" })
  h.write(dir .. "/app/tests/XTest.php", TEST)
  h.write(dir .. "/app/src/Thrower.php", THROWER)
  h.write(dir .. "/junit.xml", vim.split(JUNIT, "\n"))
  h.write(dir .. "/fake-phpunit.sh", {
    "#!/bin/sh",
    'echo "$@" >> "$ROOT/args.log"',
    'for a in "$@"; do case "$a" in --log-junit=*) log="${a#--log-junit=}";; esac; done',
    'log="$ROOT${log#/ctr}"',
    'mkdir -p "$(dirname "$log")"',
    'cp "$ROOT/junit.xml" "$log"',
    "exit 0",
  })
  vim.fn.system({ "chmod", "+x", dir .. "/fake-phpunit.sh" })
  return dir
end

local function start(dir)
  local screen = h.nvim(dir, 160, 50)
  screen:exec(string.format([[
    require("modules.phpunit").configure({
      root = %q, projects = { "app" }, paths = { [%q] = "/ctr" },
      command = "ROOT=" .. %q .. " " .. %q .. "/fake-phpunit.sh ${phpunitargs}",
    })
    require("modules.phpunit.memory").set_file(%q)
    vim.cmd("edit " .. %q)
    require("modules.phpunit.options").set_parallel(false)
    require("modules.phpunit.options").set_flat(false)
    require("modules.phpunit.pane").toggle()
  ]], dir, dir, dir, dir, dir .. "/memory.json", dir .. "/app/tests/XTest.php"))
  h.wait(screen, function()
    return screen:exec("local p = require('modules.phpunit.pane'); return p.weight(p.root_id() or '') >= 5")
  end, "the tests of XTest.php were not found")
  return screen
end

local function run_all(screen)
  screen:exec("require('modules.phpunit.runner').run_all()")
  h.wait(screen, function()
    return screen:exec("return #require('modules.phpunit.details').failures()") == 4
      and #screen:exec("return require('modules.phpunit.pane').running_ids()") == 0
  end, "the run must end with four failures (testSame, testEq, testErr, testSets \"bad\")", 20000)
end

local function to_editor(screen, line)
  screen:exec(string.format([[
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)):match("XTest%%.php$") then
        vim.api.nvim_set_current_win(win)
      end
    end
    vim.api.nvim_win_set_cursor(0, { %d, 0 })
  ]], line))
end

local function view_lines(screen)
  return screen:exec([[
    local d = require("modules.phpunit.details")
    if not d.is_open() then return {} end
    return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(vim.fn.bufwinid("phpunit://test-failure")), 0, -1, false)
  ]])
end

local function view_has(screen, text)
  for _, line in ipairs(view_lines(screen)) do
    if line:find(text, 1, true) then
      return true
    end
  end
  return false
end

lib.test("test failure: <leader>td shows the exception, the trace and the output; Enter on a frame opens that line", function()
  local dir = project()
  local screen = start(dir)
  run_all(screen)
  to_editor(screen, 14) -- inside testErr
  screen:input(" td")
  h.wait(screen, function()
    return h.find_on_screen(screen, 'RuntimeException: boom <&> "q"') ~= nil
      and h.find_on_screen(screen, "Stack trace") ~= nil
  end, "the failure view of testErr is not on the screen")
  lib.ok(view_has(screen, "Output") and view_has(screen, "   hello out"), "what the test printed")
  lib.ok(view_has(screen, "✗ XTest::testErr"), "the test is named")
  lib.ok(view_has(screen, "XTest.php:15 · 0 ms · RuntimeException"), "where it failed, how long, the exception")
  lib.ok(view_has(screen, "→ app/src/Thrower.php:6"), "the origin is marked and the path is relative")
  lib.eq("phpunit_failure", screen:exec("return vim.bo.filetype"), "the cursor is in the view")
  -- to the frame of Thrower.php, and Enter
  local row = screen:exec([[
    for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if l:find("Thrower.php:6", 1, true) then return i end
    end
  ]])
  screen:exec("vim.api.nvim_win_set_cursor(0, { " .. row .. ", 0 })")
  screen:input("<CR>")
  h.wait(screen, function()
    return screen:exec("return vim.fn.expand('%:t')") == "Thrower.php"
      and screen:exec("return vim.api.nvim_win_get_cursor(0)[1]") == 6
  end, "Enter on the frame must open Thrower.php at line 6")
  lib.ok(screen:exec("return require('modules.phpunit.details').is_open()"), "the view stays open")
  -- the line the exception came from is marked, in the code under test
  h.wait(screen, function()
    return h.find_on_screen(screen, "thrown in XTest::testErr") ~= nil
  end, "the place the exception was thrown has no mark")
  screen:close()
end)

lib.test("test failure: ]f / [f go from failure to failure, the view follows; d compares the values side by side", function()
  local dir = project()
  local screen = start(dir)
  run_all(screen)
  to_editor(screen, 1)
  screen:input("]f")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_win_get_cursor(0)[1]") == 6
  end, "]f must go to the line testSame failed on")
  screen:input("]f")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_win_get_cursor(0)[1]") == 10
  end, "the next ]f must go to testEq's line")
  screen:input("[f")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_win_get_cursor(0)[1]") == 6
  end, "[f must go back")
  screen:input(" td")
  h.wait(screen, function()
    return view_has(screen, "Expected ↔ Actual") and h.find_on_screen(screen, "Failure 1/4") ~= nil
  end, "the view of testSame shows its comparison and where it is in the list")
  -- in the view ]f shows the next one, the cursor stays there and the editor follows
  screen:input("]f")
  h.wait(screen, function()
    return view_has(screen, "✗ XTest::testEq") and view_has(screen, "Expected: 1") and view_has(screen, "Actual:   2")
  end, "]f in the view must show testEq")
  lib.eq("phpunit_failure", screen:exec("return vim.bo.filetype"))
  lib.ok(view_has(screen, "1.2 s"), "how long it took")
  screen:input("d")
  h.wait(screen, function()
    return screen:exec("return vim.wo.diff") == true
      and screen:exec("return vim.api.nvim_buf_get_name(0)"):match("phpunit://") ~= nil
  end, "d must open expected and actual as a diff")
  lib.eq({ { "1" }, { "2" } }, screen:exec([[
    local out = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_config(win).relative == "" then
        out[#out + 1] = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
      end
    end
    return out
  ]]))
  screen:input("q")
  h.wait(screen, function()
    return screen:exec("return #vim.api.nvim_list_tabpages()") == 1
  end, "q must close the comparison")
  screen:close()
end)

lib.test("test failure: a data set has its own failure, <leader>tq lists them all, durations show in the pane", function()
  local dir = project()
  local screen = start(dir)
  run_all(screen)
  local sets = screen:exec([[
    local out = {}
    for _, e in ipairs(require("modules.phpunit.details").failures()) do
      out[#out + 1] = (e.label or "-") .. "@" .. e.line
    end
    return out
  ]])
  lib.eq({ "-@6", "-@10", "-@15", '"bad"@20' }, { sets[1], sets[2], sets[3], sets[4] })
  screen:exec("vim.cmd('wincmd l')")
  screen:input(" tq")
  h.wait(screen, function()
    return screen:exec("return vim.bo.buftype") == "quickfix"
  end, "the quickfix list did not open")
  local qf = screen:exec([[
    local out = {}
    for _, i in ipairs(vim.fn.getqflist()) do out[#out + 1] = vim.fn.fnamemodify(vim.fn.bufname(i.bufnr), ":t") .. ":" .. i.lnum .. " " .. i.text end
    return out
  ]])
  lib.eq(5, #qf, vim.inspect(qf))
  lib.matches("^XTest%.php:6 XTest::testSame: Failed asserting", qf[1])
  lib.matches("^Thrower%.php:6   thrown here for XTest::testErr", qf[4])
  lib.matches('^XTest%.php:20 XTest::testSets "bad": Failed asserting that false is true', qf[5])
  -- the pane: expand the file, testEq took 1.2 s
  screen:exec("vim.cmd('cclose')")
  screen:exec("require('modules.phpunit.pane').panes()[1]:action('tests_expand_all')")
  h.wait(screen, function()
    return h.find_on_screen(screen, "testEq  1.2 s") ~= nil
  end, "the pane must show how long testEq took")
  screen:close()
end)

lib.test("test failure: the pane's d opens the view, moving in the pane changes what it shows; it survives a restart", function()
  local dir = project()
  local screen = start(dir)
  run_all(screen)
  screen:exec([[
    local p = require('modules.phpunit.pane').panes()[1]
    p:focus("list")
  ]])
  -- the Failed section is open: its first row is testSame (once the pane shows the results)
  local first
  h.wait(screen, function()
    first = screen:exec([[
      local p = require('modules.phpunit.pane').panes()[1]
      for i, item in ipairs(p:items()) do
        if item.kind == "test" and item.status == "failed" then p.list:move(i, true); return item.name end
      end
    ]])
    return first ~= nil
  end, "the pane shows no failed test")
  lib.eq("testSame", first)
  screen:input("d")
  h.wait(screen, function()
    return view_has(screen, "✗ XTest::testSame")
  end, "d in the pane did not show the failure of testSame")
  screen:exec([[
    local p = require('modules.phpunit.pane').panes()[1]
    p:focus("list")
    for i, item in ipairs(p:items()) do if item.kind == "test" and item.name == "testErr" then p.list:move(i, true) end end
  ]])
  h.wait(screen, function()
    return view_has(screen, "✗ XTest::testErr")
  end, "the view did not follow the pane's cursor")
  h.wait(screen, function() -- the results are saved a moment after they come in
    local file = dir .. "/memory.json"
    return vim.fn.filereadable(file) == 1 and table.concat(vim.fn.readfile(file)):find("Thrower", 1, true) ~= nil
  end, "the failures were not saved")
  screen:close()

  -- a new session: the failure, its trace and output are still there
  local again = start(dir)
  h.wait(again, function()
    return again:exec("return #require('modules.phpunit.details').failures()") == 4
  end, "the failures were not remembered")
  to_editor(again, 14)
  again:input(" td")
  h.wait(again, function()
    return view_has(again, "→ app/src/Thrower.php:6") and view_has(again, "hello out")
  end, "the remembered failure lost its trace or output")
  again:close()
end)

local function backdrops(screen)
  return screen:exec([[
    local n = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.wo[win].winhighlight:find("ModalBackdrop", 1, true) then n = n + 1 end
    end
    return n
  ]])
end

lib.test("test failure: ? in the view and in the pane lists every key, over a dimmed screen", function()
  local dir = project()
  local screen = start(dir)
  run_all(screen)
  to_editor(screen, 6)
  screen:input(" td")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype") == "phpunit_failure"
  end, "the view did not open")
  screen:input("?")
  h.wait(screen, function()
    return h.find_on_screen(screen, "Test failure keys") ~= nil
  end, "? did not show the keys of the view")
  -- every key the view maps is in the list
  local keys = screen:exec([[
    local listed = {}
    for _, k in ipairs(require("modules.phpunit.details").KEYS) do listed[#listed + 1] = k[1] end
    local text = table.concat(listed, " ")
    local missing = {}
    for _, key in ipairs(require("modules.phpunit.details").mapped) do
      local lhs = key:gsub("<2%-LeftMouse>", "2-click"):gsub("<S%-Tab>", "Shift+Tab"):gsub("<CR>", "Enter"):gsub("<Tab>", "Tab")
      if not text:find(lhs, 1, true) then missing[#missing + 1] = key end
    end
    return missing
  ]])
  lib.eq({}, keys, "keys of the view missing from its ? list")
  for _, k in ipairs({ "expected and actual side by side", "next / previous failure", "copy the failure" }) do
    lib.ok(h.find_on_screen(screen, k) ~= nil, "not on screen: " .. k)
  end
  lib.eq(1, backdrops(screen), "the screen behind the keys is dimmed")
  screen:input("q")
  h.wait(screen, function()
    return h.find_on_screen(screen, "Test failure keys") == nil and backdrops(screen) == 0
  end, "q did not close the keys and their backdrop")
  -- the pane's ? has the new key too
  screen:exec("require('modules.phpunit.pane').panes()[1]:focus('list')")
  screen:input("?")
  h.wait(screen, function()
    return h.find_on_screen(screen, "Tests pane keys") ~= nil and h.find_on_screen(screen, "failure details") ~= nil
  end, "the pane's ? does not list d (failure details)")
  lib.eq(1, backdrops(screen), "the screen behind the pane's keys is dimmed")
  screen:close()
end)
