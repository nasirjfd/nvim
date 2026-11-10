-- The tests pane (Cmd+Shift+T, neotest) and PHPUnit through a command template with container paths
-- (lua/modules/phpunit): the command line, the path mapping, the junit log, a real run with a fake phpunit,
-- and the pane in the window layout.
local lib = require("lib")
local h = require("support")

-- ── the command line (pure) ─────────────────────────────────────────────────────────────────────
package.path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h") .. "/lua/?.lua;" .. package.path
local plan = require("modules.phpunit.plan")

lib.test("phpunit plan: paths map to the container and back, the longest folder wins", function()
  local dir = h.tmpdir()
  h.write(dir .. "/a/b.php", { "x" })
  plan.configure({ root = dir, paths = { [dir] = "/var/www/vendor", [dir .. "/a"] = "/other" } })
  lib.eq("/var/www/vendor/zzz/x.php", plan.to_container(dir .. "/zzz/x.php"))
  lib.eq("/other/b.php", plan.to_container(dir .. "/a/b.php"))
  lib.eq(dir .. "/zzz/x.php", plan.to_host("/var/www/vendor/zzz/x.php"))
  lib.eq(dir .. "/a/b.php", plan.to_host("/other/b.php"))
  lib.eq("/elsewhere/x", plan.to_container("/elsewhere/x"), "a path no folder maps stays as it is")
  lib.eq("/var/www/vendorx/y", plan.to_host("/var/www/vendorx/y"), "a prefix is not a folder")
  plan.reset()
end)

lib.test("phpunit plan: a file runs in its project with the project's config; a folder above runs every project", function()
  local dir = h.tmpdir()
  h.write(dir .. "/p1/tests.xml", { "<phpunit/>" })
  h.write(dir .. "/p1/tests/ATest.php", { "x" })
  h.write(dir .. "/g/p2/phpunit.xml", { "<phpunit/>" })
  h.write(dir .. "/g/p2/tests/BTest.php", { "x" })
  plan.configure({ root = dir, projects = { "p1", "g/p2" }, paths = { [dir] = "/c" } })
  local file = plan.norm(dir) .. "/p1/tests/ATest.php"
  local t = plan.targets(file)
  lib.eq({ { project = plan.norm(dir) .. "/p1", path = file } }, t)
  lib.eq({ "--configuration=/c/p1/tests.xml", "/c/p1/tests/ATest.php", "--log-junit=/c/.neotest-results/r.xml" },
    plan.args(t[1], dir .. "/.neotest-results/r.xml"))
  lib.eq({ "--configuration=/c/p1/tests.xml", "--log-junit=/c/.neotest-results/r.xml" },
    plan.args({ project = t[1].project, path = t[1].project }, dir .. "/.neotest-results/r.xml"), "a whole project needs no path")
  local all = plan.targets(dir)
  lib.eq(2, #all, "the root runs both projects")
  lib.eq({ "--configuration=/c/g/p2/phpunit.xml", "--log-junit=/c/.neotest-results/r.xml" },
    plan.args(all[2], dir .. "/.neotest-results/r.xml"))
  lib.eq({}, plan.targets(dir .. "/elsewhere/../../nothing"), "a path in no project runs nothing")
  local with_test = plan.args(t[1], dir .. "/.neotest-results/r.xml", "testIt")
  lib.eq({ "--filter", "::testIt( with data set .*)?$" }, { with_test[4], with_test[5] })
  plan.reset()
end)

lib.test("phpunit plan: --configuration in args (like the VS Code setting) limits the tests to that project", function()
  local dir = h.tmpdir()
  h.write(dir .. "/g/one/tests.xml", { "<phpunit/>" })
  h.write(dir .. "/g/one/tests/ATest.php", { "x" })
  h.write(dir .. "/g/two/tests.xml", { "<phpunit/>" })
  h.write(dir .. "/g/two/tests/BTest.php", { "x" })
  plan.configure({ root = dir, args = { "--configuration=g/one/tests.xml", "--no-interaction" }, paths = { [dir] = "/c" } })
  local root = plan.norm(dir)
  lib.eq({ root .. "/g/one" }, plan.get().projects)
  lib.eq({ "--no-interaction" }, plan.get().args, "the configuration is not given twice")
  lib.ok(plan.project_of(root .. "/g/one/tests/ATest.php"), "a file of the configured project belongs to it")
  lib.eq(nil, plan.project_of(root .. "/g/two/tests/BTest.php"), "a file of another project does not")
  local t = plan.targets(root .. "/g/one/tests/ATest.php")
  lib.eq("--configuration=/c/g/one/tests.xml", plan.args(t[1], dir .. "/r.xml")[1])
  lib.eq("php --no-interaction", (plan.command({}):gsub("^php %S*%s*vendor/bin/phpunit ", "php ")), "the other arguments stay")
  -- both spellings, and an explicit list of projects wins
  plan.configure({ root = dir, args = { "--configuration", "g/two/tests.xml" } })
  lib.eq({ root .. "/g/two" }, plan.get().projects)
  plan.configure({ root = dir, args = { "--configuration=g/one/tests.xml" }, projects = { "g/one", "g/two" } })
  lib.eq(2, #plan.get().projects)
  plan.reset()
end)

lib.test("phpunit plan: the VS Code command template is filled in and the arguments survive both shells", function()
  local dir = h.tmpdir()
  plan.configure({
    root = dir,
    command = [[/bin/sh -c "printf '<%s>' ${php} ${phpargs} ${phpunitargs}"]],
    args = { "--no-interaction" },
  })
  local cmd = plan.command({ "--filter", "::testIt( with data set .*)?$", "/a b/it's.php", "$HOME `x` \"q\"" })
  local out = vim.system({ "/bin/sh", "-c", cmd }, { text = true }):wait()
  lib.eq(0, out.code, out.stderr)
  lib.eq("<php><--no-interaction><--filter><::testIt( with data set .*)?$></a b/it's.php><$HOME `x` \"q\">", out.stdout)
  -- outside double quotes the arguments are only quoted once
  plan.configure({ root = dir, command = "printf '<%s>' ${phpunitargs} ${workspaceFolder}" })
  local plain = vim.system({ "/bin/sh", "-c", plan.command({ "a b", "it's" }) }, { text = true }):wait()
  lib.eq("<a b><it's><" .. plan.norm(dir) .. ">", plain.stdout)
  plan.reset()
end)

-- ── the junit log ───────────────────────────────────────────────────────────────────────────────
local JUNIT = [[<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="all" tests="6">
    <testsuite name="Foo" file="/p/FooTest.php" tests="5">
      <testcase name="testPass" class="Foo" file="/p/FooTest.php" line="5" assertions="1" time="0.1"/>
      <testcase name="testFail" class="Foo" file="/p/FooTest.php" line="9" assertions="1" time="0.1">
        <failure type="PHPUnit\Framework\ExpectationFailedException">Foo::testFail
Failed asserting that false is true.

/p/FooTest.php:11</failure>
      </testcase>
      <testcase name="testSkip" class="Foo" file="/p/FooTest.php" line="14" assertions="0"><skipped/></testcase>
      <testcase name="testData with data set #0" class="Foo" file="/p/FooTest.php" line="20" assertions="1"/>
      <testcase name="testData with data set #1" class="Foo" file="/p/FooTest.php" line="20" assertions="1">
        <error type="Error">Foo::testData with data set #1
Error: boom</error>
      </testcase>
    </testsuite>
    <testsuite name="Bar" file="/p/BarTest.php" tests="1">
      <testcase name="Bar\BarTest::testSetup" assertions="0">
        <error type="Error">Bar\BarTest::testSetup
Error: class not found</error>
      </testcase>
    </testsuite>
  </testsuite>
</testsuites>]]

lib.test("phpunit junit: pass, fail with its line, skip, data sets, a case without a file (setUpBeforeClass)", function()
  local screen = h.nvim(h.tmpdir())
  local r = screen:exec("return require('modules.phpunit.junit').from_text(...)", { JUNIT })
  lib.eq("passed", r["/p/FooTest.php::testPass"].status)
  lib.eq("failed", r["/p/FooTest.php::testFail"].status)
  lib.eq(10, r["/p/FooTest.php::testFail"].errors[1].line, "the failing line of the test file (0-based)")
  lib.matches("Failed asserting", r["/p/FooTest.php::testFail"].short)
  lib.eq("skipped", r["/p/FooTest.php::testSkip"].status)
  lib.eq("failed", r["/p/FooTest.php::testData"].status, "one failing data set fails the method")
  lib.eq("failed", r["/p/BarTest.php::testSetup"].status, "a case without file takes the file of its suite")
  screen:close()
end)

lib.test("phpunit junit: a single testcase or a single suite (not a list) is read too", function()
  local screen = h.nvim(h.tmpdir())
  local one = [[<testsuites><testsuite name="S" file="/p/ATest.php"><testcase name="testOne" file="/p/ATest.php" line="3"/></testsuite></testsuites>]]
  local r = screen:exec("return require('modules.phpunit.junit').from_text(...)", { one })
  lib.eq("passed", r["/p/ATest.php::testOne"].status)
  screen:close()
end)

-- ── a run through a fake container ──────────────────────────────────────────────────────────────
-- The fake phpunit sees container paths (/ctr/...) like phpunit in Docker does and writes its log there; its
-- results name the files as /ctr/... so the mapping back to the host is tested too.
local function fake_project()
  local dir = vim.fn.resolve(h.tmpdir())
  h.write(dir .. "/app/tests.xml", { "<phpunit/>" })
  h.write(dir .. "/app/tests/FooTest.php", {
    "<?php",
    "class FooTest extends \\PHPUnit\\Framework\\TestCase",
    "{",
    "    public function testPasses()",
    "    {",
    "    }",
    "",
    "    public function testFails()",
    "    {",
    "        $this->assertTrue(false);",
    "    }",
    "}",
  })
  h.write(dir .. "/fake-phpunit.sh", {
    "#!/bin/sh",
    'echo "$@" >> "$ROOT/args.log"',
    'for a in "$@"; do case "$a" in --log-junit=*) log="${a#--log-junit=}";; esac; done',
    'log="$ROOT${log#/ctr}"',
    "mkdir -p \"$(dirname \"$log\")\"",
    "cat > \"$log\" <<XML",
    '<testsuites><testsuite name="FooTest" file="/ctr/app/tests/FooTest.php">',
    '<testcase name="testPasses" class="FooTest" file="/ctr/app/tests/FooTest.php" line="4"/>',
    '<testcase name="testFails" class="FooTest" file="/ctr/app/tests/FooTest.php" line="8"><failure type="X">FooTest::testFails',
    "Failed asserting that false is true.",
    "",
    "/ctr/app/tests/FooTest.php:10</failure></testcase>",
    "</testsuite></testsuites>",
    "XML",
    'echo "FAKE PHPUNIT OUTPUT"',
    "exit 1",
  })
  vim.fn.system({ "chmod", "+x", dir .. "/fake-phpunit.sh" })
  return dir
end


-- the counts of the neotest tree: { passed, failed, skipped, total }
local function counts(screen)
  screen:exec([[
    _G.nt_counts = nil
    require("nio").run(function()
      local ids = require("neotest").state.adapter_ids()
      _G.nt_counts = ids[1] and require("neotest").state.status_counts(ids[1]) or false
    end)
  ]])
  h.wait(screen, function()
    return screen:exec("return _G.nt_counts ~= nil")
  end, "no counts")
  return screen:exec("return _G.nt_counts")
end

local function start_neotest(screen, dir)
  -- configure() has to come first, like a project's .nvim.lua does
  screen:exec(string.format([[
    require("modules.phpunit").configure({
      root = %q, projects = { "app" }, paths = { [%q] = "/ctr" },
      command = "ROOT=" .. %q .. " " .. %q .. "/fake-phpunit.sh ${phpunitargs}",
    })
    vim.cmd("edit " .. %q)
    require("neotest")
  ]], dir, dir, dir, dir, dir .. "/app/tests/FooTest.php"))
  h.wait(screen, function()
    return (counts(screen) or {}).total == 2
  end, "the two tests were not discovered")
end

lib.test("phpunit run: a file runs once through the command with container paths, results map back", function()
  local dir = fake_project()
  local screen = h.nvim(dir)
  start_neotest(screen, dir)
  screen:exec(string.format([[require("neotest").run.run(%q)]], dir .. "/app/tests/FooTest.php"))
  h.wait(screen, function()
    local c = counts(screen)
    return c and c.passed == 1 and c.failed == 1
  end, "the run did not give one pass and one failure")
  local args = h.read(dir .. "/args.log")
  lib.eq(1, #args, "phpunit ran once")
  lib.matches("^%-%-configuration=/ctr/app/tests%.xml /ctr/app/tests/FooTest%.php %-%-log%-junit=/ctr/%.neotest%-results/", args[1])
  lib.ok(not args[1]:find("--filter", 1, true), "a file is not filtered")
  lib.eq(0, #vim.fn.glob(dir .. "/.neotest-results/*", false, true), "the junit log is removed after the run")
  screen:close()
end)

local function logged(dir)
  return vim.fn.filereadable(dir .. "/args.log") == 1 and h.read(dir .. "/args.log") or {}
end

lib.test("phpunit run: the nearest test runs with --filter, a project folder runs without a path", function()
  local dir = fake_project()
  local screen = h.nvim(dir)
  start_neotest(screen, dir)
  screen:exec(string.format([[require("neotest").run.run(%q)]], dir))
  h.wait(screen, function()
    return #logged(dir) == 1
  end, "the root did not run")
  lib.eq("--configuration=/ctr/app/tests.xml", logged(dir)[1]:match("^(%S+)"))
  lib.ok(not logged(dir)[1]:find("tests/FooTest", 1, true), "the project is run as a whole")
  -- the test under the cursor
  screen:exec("vim.api.nvim_win_set_cursor(0, { 10, 0 })")
  screen:exec("require('neotest').run.run()")
  h.wait(screen, function()
    return #logged(dir) == 2
  end, "the nearest test did not run")
  lib.matches("/ctr/app/tests/FooTest%.php .*%-%-filter ::testFails%(", logged(dir)[2])
  screen:close()
end)

lib.test("phpunit run: when phpunit writes no log the run shows as failed with the output", function()
  local dir = fake_project()
  h.write(dir .. "/fake-phpunit.sh", { "#!/bin/sh", "echo 'Fatal: no docker'", "exit 125" })
  local screen = h.nvim(dir)
  start_neotest(screen, dir)
  screen:exec(string.format([[require("neotest").run.run(%q)]], dir .. "/app/tests/FooTest.php"))
  h.wait(screen, function()
    local c = counts(screen)
    return c and c.failed >= 1
  end, "a run without a log must show as failed")
  screen:close()
end)

-- ── the pane ────────────────────────────────────────────────────────────────────────────────────
local function layout(screen)
  return screen:exec([[
    local heights = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_config(win).relative == "" then
        heights[#heights + 1] = vim.api.nvim_win_get_height(win)
      end
    end
    local panes = require("modules.phpunit.pane").panes()
    return { cmdheight = vim.o.cmdheight, lines = vim.o.lines, heights = heights, summary = #panes,
      focused = #panes > 0 and panes[1].list.win.win == vim.api.nvim_get_current_win() }
  ]])
end

local function press(screen, key)
  screen:exec("vim.fn.maparg(..., 'n', false, true).callback()", { key })
end

lib.test("tests pane: Cmd+Shift+T opens it with the focus, focuses it from elsewhere, closes it from inside", function()
  local screen = h.nvim(fake_project())
  lib.ok(screen:exec("return vim.fn.maparg('<D-S-t>', 'n') ~= ''"), "Cmd+Shift+T is not mapped")
  press(screen, "<D-S-t>")
  h.wait(screen, function()
    local l = layout(screen)
    return l.summary == 1 and l.focused
  end, "the pane did not open with the focus")
  screen:input("<C-w>l") -- away from it
  h.wait(screen, function()
    return not layout(screen).focused
  end, "could not leave the pane")
  press(screen, "<D-S-t>")
  h.wait(screen, function()
    return layout(screen).focused
  end, "the open pane was not focused")
  press(screen, "<D-S-t>")
  h.wait(screen, function()
    return layout(screen).summary == 0
  end, "the focused pane was not closed")
  screen:close()
end)

lib.test("tests pane: next to the Explorer and the HTTP pane the layout stays whole", function()
  local dir = fake_project()
  local screen = h.nvim(dir)
  local function whole(label)
    vim.wait(300)
    screen:flush()
    local l = layout(screen)
    lib.eq(1, l.cmdheight, label .. ": the command line grew")
    for _, height in ipairs(l.heights) do
      lib.ok(height >= l.lines - 3, label .. ": a window is only " .. height .. " rows tall " .. vim.inspect(l.heights))
    end
  end
  for _, step in ipairs({ "<D-S-t>", "<D-S-e>", "<D-S-t>", "<D-S-t>", "<D-S-e>", "<D-S-t>" }) do
    press(screen, step)
    whole(step)
  end
  screen:exec("vim.fn.maparg('<leader>h', 'n', false, true).callback()")
  whole("http pane next to the tests pane")
  screen:close()
end)
