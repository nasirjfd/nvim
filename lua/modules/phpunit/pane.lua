-- The Tests pane (Cmd+Shift+T): a sidebar like the Explorer that lists the tests neotest found, as
-- "parent folder -> test file -> every test method", with their last result, and a few rows on top: the
-- counts, the Parallel checkbox, Run all and Run failed.
--
-- neotest is the engine (finding tests, running them, the results, the signs in the files); this is only a
-- view of its state, kept in `snap` by a neotest consumer (see attach), plus the keys that start runs
-- (runner.lua). It is a Snacks picker source, like the HTTP Requests pane.
local kit = require("modules.pane_kit")
local options = require("modules.phpunit.options")
local plan = require("modules.phpunit.plan")

local M = {}

local SOURCE = "phpunit_tests"
local TITLE = "Tests"
local api = vim.api
local uv = vim.uv

kit.register(SOURCE, TITLE)

-- ── the state of neotest, as seen by this pane ──────────────────────────────────────────────────
local snap = {
  tree = nil, ---@type neotest.Tree?
  results = {}, ---@type table<string, neotest.Result>
  running = {}, ---@type table<string, any>
  adapter = nil, ---@type string?
}
local last_status = {} -- test id -> what it last was (passed/failed/skipped): a test that runs keeps its place
local last_results = {} -- test id -> its last result (kept while a run clears it)
local known_sets = {} -- test id -> how many data sets it had last time (a run's size is counted in these)
local expanded = {} -- file key -> true while its tests are shown
local collapsed = {} -- folder key -> true while folded

local function runner()
  return require("modules.phpunit.runner")
end

local timer
local function refresh_soon()
  timer = timer or assert(uv.new_timer())
  timer:stop()
  timer:start(
    60,
    0,
    vim.schedule_wrap(function()
      for _, picker in ipairs(M.panes()) do
        kit.refresh(picker)
      end
    end)
  )
end

--- Called by neotest (a consumer, see lua/plugins/neotest.lua) with its client: follow its state.
function M.attach(client)
  local memory = require("modules.phpunit.memory")
  local pending ---@type table<string, table>? remembered results not put back yet
  local saving

  local function is_test(id)
    local node = snap.tree and snap.tree:get_key(id)
    return node ~= nil and node:data().type == "test"
  end

  local function update(adapter_id)
    local tree = client:get_position(nil, { adapter = adapter_id })
    snap.adapter, snap.tree = adapter_id, tree
    snap.results = client:get_results(adapter_id) or {}
    for id, result in pairs(snap.results) do
      last_status[id] = result.status
      if id:find("::", 1, true) then
        last_results[id] = result
      end
      if result.datasets then
        known_sets[id] = #result.datasets
      end
    end
    local ok, running = pcall(function()
      return client._state:running(adapter_id)
    end)
    snap.running = ok and running or {}
    refresh_soon()
    -- keep what the tests did for the next session
    if tree and not saving then
      saving = true
      vim.defer_fn(function()
        saving = false
        if snap.tree then
          pcall(memory.remember, snap.tree:data().id, snap.results, is_test)
        end
      end, 800)
    end
  end

  -- Put back what the last session knew, for the tests found so far that have no result yet.
  local function restore(adapter_id)
    if not snap.tree then
      return
    end
    pending = pending or memory.recall(snap.tree:data().id)
    local back = {}
    for id, result in pairs(pending) do
      if is_test(id) then
        pending[id] = nil
        if not snap.results[id] then
          back[id] = result
        end
      end
    end
    if next(back) then
      pcall(function()
        client._state:update_results(adapter_id, back)
      end)
    end
  end

  require("modules.phpunit.progress").on_change = function()
    refresh_soon()
  end

  client.listeners.discover_positions = function(adapter_id)
    update(adapter_id)
    restore(adapter_id)
  end
  client.listeners.run = function(adapter_id)
    update(adapter_id)
  end
  client.listeners.results = function(adapter_id)
    update(adapter_id)
  end
  -- neotest starts looking for tests when something first asks it for them
  snap.sync = function()
    require("nio").run(function()
      local ids = client:get_adapters()
      if ids[1] then
        update(ids[1])
        restore(ids[1])
      end
    end)
  end
  snap.sync()
end

-- ── what the keys need to know ──────────────────────────────────────────────────────────────────
--- What the pane knows of neotest right now (for tests).
function M.snapshot()
  return snap
end

function M.root_id()
  return snap.tree and snap.tree:data().id
end

local function node_of(id)
  return snap.tree and snap.tree:get_key(id)
end

--- The ids of the test files under a position (a folder, or the file itself).
---@return string[]?
function M.files_under(id)
  local node = node_of(id)
  if not node then
    return nil
  end
  local found = {}
  for _, child in node:iter_nodes() do
    if child:data().type == "file" then
      found[#found + 1] = child:data().id
    end
  end
  return found
end

function M.file_id(path)
  local id = plan.norm(path)
  local node = node_of(id)
  return node and node:data().type == "file" and id or nil
end

--- The test the cursor (0-based `row`) is in or below: the last one that starts at or above it; the file
--- when none does.
function M.nearest(path, row)
  local file = M.file_id(path)
  if not file then
    return nil
  end
  local best, best_row
  for _, node in node_of(file):iter_nodes() do
    local data = node:data()
    if data.type == "test" and data.range and data.range[1] <= row and (not best_row or data.range[1] >= best_row) then
      best, best_row = data.id, data.range[1]
    end
  end
  return best or file
end

--- The tests that failed in their last run: names by file, and the files.
---@return table<string, string[]>, string[]
function M.failed()
  local only, files = {}, {}
  if not snap.tree then
    return only, files
  end
  for _, node in snap.tree:iter_nodes() do
    local data = node:data()
    local result = data.type == "test" and snap.results[data.id]
    if result and result.status == "failed" then
      if not only[data.path] then
        only[data.path] = {}
        files[#files + 1] = data.path
      end
      -- a method with data sets: only the data sets that failed
      local failed_sets = {}
      for _, set in ipairs(result.datasets or {}) do
        if set.status == "failed" then
          failed_sets[#failed_sets + 1] = data.name .. " with data set " .. set.label
        end
      end
      if #failed_sets > 0 and #failed_sets < #result.datasets then
        vim.list_extend(only[data.path], failed_sets)
      else
        table.insert(only[data.path], data.name)
      end
    end
  end
  table.sort(files)
  return only, files
end

--- How many runs of tests a position probably is: each test counts for its data sets as of last time. With `only`
--- (names, as of `failed()`) just those.
function M.weight(id, only)
  local node = node_of(id)
  if not node then
    return 0
  end
  local wanted
  if only then
    wanted = {}
    for _, name in ipairs(only) do
      wanted[name] = true
    end
  end
  local total = 0
  for _, child in node:iter_nodes() do
    local data = child:data()
    if data.type == "test" then
      if not wanted then
        total = total + (known_sets[data.id] or 1)
      elseif wanted[data.name] then
        total = total + (known_sets[data.id] or 1)
      else
        for name in pairs(wanted) do
          if name:sub(1, #data.name + 15) == data.name .. " with data set " then
            total = total + 1
          end
        end
      end
    end
  end
  return total
end

--- The last result of a test (nil when it never had one).
function M.last_result(id)
  return last_results[id]
end

--- Whether `id` is a single test (not a file or folder).
function M.test_ids(id)
  local node = node_of(id)
  return node and node:data().type == "test" or nil
end

function M.running_ids()
  return vim.tbl_keys(snap.running or {})
end

-- ── rows ────────────────────────────────────────────────────────────────────────────────────────
-- A run of just some tests of a file (Run failed, one test, one data set): neotest marks every test of the file as
-- running and drops their results while it goes. Only the ones that really run show as running, the others keep
-- what they were.
local narrow ---@type table<string, boolean>?

--- Limit what shows as running to these test ids (nil: everything neotest says runs).
function M.narrow(ids)
  narrow = ids
  refresh_soon()
end

local function running_now(id)
  return snap.running[id] and (not narrow or narrow[id])
end

local function result_of(id)
  local result = snap.results[id]
  if result then
    return result
  end
  if narrow and snap.running[id] and not narrow[id] then
    return last_results[id]
  end
end

--- The ids of the tests of `file` that `names` ("method" or "method with data set LABEL") are.
function M.ids_for(file, names)
  local ids = {}
  local node = node_of(file)
  if not node then
    return ids
  end
  for _, child in node:iter_nodes() do
    local data = child:data()
    if data.type == "test" then
      for _, name in ipairs(names) do
        if name == data.name or name:sub(1, #data.name + 15) == data.name .. " with data set " then
          ids[data.id] = true
        end
      end
    end
  end
  return ids
end

-- What a test counts as: one, or one per data set once PHPUnit has run it (the number of runs is what PHPUnit reports)
local function sets_of(test)
  local result = result_of(test.id)
  return result and result.datasets or nil
end

local function counts_of(tests)
  local c = { passed = 0, failed = 0, skipped = 0, running = 0, total = 0 }
  for _, test in ipairs(tests) do
    if running_now(test.id) then
      -- a test that runs counts as many runs as it had data sets last time (what progress counts too)
      local weight = known_sets[test.id] or 1
      c.running, c.total = c.running + weight, c.total + weight
    else
      local result = result_of(test.id)
      local sets = result and result.datasets
      if sets and #sets > 0 then
        for _, set in ipairs(sets) do
          c.total = c.total + 1
          if c[set.status] then
            c[set.status] = c[set.status] + 1
          end
        end
      else
        c.total = c.total + (result and 1 or (known_sets[test.id] or 1))
        if result and c[result.status] then
          c[result.status] = c[result.status] + 1
        end
      end
    end
  end
  return c
end

local function status_of(c)
  if c.running > 0 then
    return "running"
  elseif c.failed > 0 then
    return "failed"
  elseif c.total > 0 and c.passed == c.total then
    return "passed"
  elseif c.passed + c.skipped > 0 and c.passed + c.skipped == c.total then
    return c.passed > 0 and "passed" or "skipped"
  end
  return "none"
end

local function sorted_keys(t)
  local keys = vim.tbl_keys(t)
  table.sort(keys)
  return keys
end

-- every file of the tree with its tests: { { id, name, dir, tests = { {id, name, line} } } }
local function collect()
  local list = {}
  if not snap.tree then
    return list
  end
  for _, node in snap.tree:iter_nodes() do
    local data = node:data()
    if data.type == "file" then
      local file = { id = data.id, path = data.path, name = vim.fs.basename(data.path), dir = vim.fs.dirname(data.path), tests = {} }
      for _, child in node:iter_nodes() do
        local c = child:data()
        if c.type == "test" then
          file.tests[#file.tests + 1] = { id = c.id, name = c.name, line = c.range and c.range[1] + 1 or 1, path = c.path }
        end
      end
      list[#list + 1] = file
    end
  end
  return list
end

local function rows(_, ctx)
  local searching = ctx and ctx.filter and ctx.filter.pattern and ctx.filter.pattern ~= ""
  local files = collect()
  local all = {}
  for _, file in ipairs(files) do
    vim.list_extend(all, file.tests)
  end
  local total = counts_of(all)
  local items = {
    { text = "Tests", kind = "info", counts = total, discovering = snap.tree == nil, key = "h:info" },
    { text = "Summary", kind = "summary", counts = total, methods = #all, discovering = snap.tree == nil, key = "h:summary" },
    { text = "Parallel", kind = "toggle", key = "h:parallel" },
    { text = "Run all", kind = "button", failed = total.failed, key = "h:run" },
  }
  -- while tests run: how far, from 0 to the last one
  local running = require("modules.phpunit.progress").state()
  if running then
    table.insert(items, 3, { text = "Progress", kind = "progress", progress = running, key = "h:progress" })
  end

  local function test_item(test, extra)
    local base = vim.fs.basename(test.path)
    return vim.tbl_extend("force", {
      text = test.name .. " " .. base,
      name = test.name,
      kind = "test",
      key = test.id,
      ids = { test.id },
      id = test.id,
      file = test.path,
      line = test.line,
      status = running_now(test.id) and "running" or (result_of(test.id) or {}).status or "none",
      sets = (not running_now(test.id)) and sets_of(test) and #sets_of(test) or nil,
    }, extra or {})
  end

  -- one data set of a method, as a row of its own
  local function set_item(test, set, extra)
    local base = vim.fs.basename(test.path)
    return vim.tbl_extend("force", {
      text = test.name .. " " .. set.label .. " " .. base,
      name = test.name,
      label = set.label,
      kind = "dataset",
      key = "s:" .. test.id .. ":" .. set.label,
      ids = { test.id },
      only_name = test.name .. " with data set " .. set.label,
      id = test.id,
      file = test.path,
      line = test.line,
      status = set.status,
      short = set.short,
    }, extra or {})
  end

  -- the rows of a test in a list that shows executions: the method, or one row per data set
  local function execution_rows(test, extra)
    local sets = (not running_now(test.id)) and sets_of(test)
    if sets and #sets > 0 then
      local rows = {}
      for _, set in ipairs(sets) do
        rows[#rows + 1] = set_item(test, set, extra)
      end
      return rows
    end
    return { test_item(test, extra) }
  end

  -- flat: every test on its own row, the failed ones first
  if options.flat() then
    local list = {}
    for _, file in ipairs(files) do
      for _, test in ipairs(file.tests) do
        vim.list_extend(list, execution_rows(test, { flat = true, file_name = vim.fs.basename(test.path) }))
      end
    end
    -- failed first; a test that runs stays where it was (it must not jump to the top and back)
    local rank = { failed = 0 }
    local function rank_of(item)
      local status = item.status == "running" and last_status[item.id] or item.status
      return rank[status] or 1
    end
    local indexed = {}
    for i, item in ipairs(list) do
      indexed[i] = { item = item, i = i }
    end
    table.sort(indexed, function(a, b)
      local ra, rb = rank_of(a.item), rank_of(b.item)
      if ra ~= rb then
        return ra < rb
      end
      return a.i < b.i
    end)
    for _, entry in ipairs(indexed) do
      items[#items + 1] = entry.item
    end
    return items
  end

  -- the failed tests first, in a section of their own
  local failed_rows = {}
  for _, file in ipairs(files) do
    for _, test in ipairs(file.tests) do
      for _, row in ipairs(execution_rows(test, { file_name = vim.fs.basename(test.path) })) do
        -- (a failed test that runs again stays in the section, running, until its result is in)
        if row.status == "failed" or (row.status == "running" and last_status[test.id] == "failed") then
          row.key = "x:" .. row.key
          failed_rows[#failed_rows + 1] = row
        end
      end
    end
  end
  if #failed_rows > 0 then
    local header = {
      text = "Failed", kind = "failed", key = "x:failed", open = searching or not collapsed["x:failed"], count = #failed_rows,
    }
    items[#items + 1] = header
    if header.open then
      for i, row in ipairs(failed_rows) do
        row.parent, row.last = header, i == #failed_rows
        items[#items + 1] = row
      end
    end
  end

  -- group the files by their parent folder
  local groups = {}
  for _, file in ipairs(files) do
    groups[file.dir] = groups[file.dir] or { dir = file.dir, files = {} }
    table.insert(groups[file.dir].files, file)
  end
  local ordered = {}
  for _, dir in ipairs(sorted_keys(groups)) do
    ordered[#ordered + 1] = groups[dir]
  end
  local dirs = vim.tbl_keys(groups)
  local count_of_name = {}
  for _, dir in ipairs(dirs) do
    local name = vim.fs.basename(dir)
    count_of_name[name] = (count_of_name[name] or 0) + 1
  end

  for gi, group in ipairs(ordered) do
    local tests = {}
    local file_ids = {}
    for _, file in ipairs(group.files) do
      vim.list_extend(tests, file.tests)
      file_ids[#file_ids + 1] = file.id
    end
    local key = "g:" .. group.dir
    local project = plan.project_of(group.dir)
    local gitem = {
      text = vim.fs.basename(group.dir),
      kind = "dir",
      key = key,
      last = gi == #ordered,
      open = searching or not collapsed[key],
      counts = counts_of(tests),
      ids = file_ids,
      project = project and vim.fs.basename(project) or nil,
      dirpath = group.dir,
    }
    items[#items + 1] = gitem
    if gitem.open then
      for fi, file in ipairs(group.files) do
        local fkey = "f:" .. file.id
        local fitem = {
          text = file.name,
          kind = "file",
          key = fkey,
          parent = gitem,
          last = fi == #group.files,
          open = searching or expanded[fkey] == true,
          counts = counts_of(file.tests),
          ids = { file.id },
          file = file.path,
          line = 1,
        }
        items[#items + 1] = fitem
        if fitem.open then
          for ti, test in ipairs(file.tests) do
            local titem = test_item(test, {
              text = test.name,
              parent = fitem,
              last = ti == #file.tests,
              open = searching or expanded["t:" .. test.id] == true,
            })
            items[#items + 1] = titem
            if titem.sets and titem.open then
              for si, set in ipairs(sets_of(test)) do
                items[#items + 1] = set_item(test, set, { parent = titem, last = si == #sets_of(test), text = test.name .. " " .. set.label })
              end
            end
          end
        end
      end
    end
  end
  return items
end

-- ── how a row looks ─────────────────────────────────────────────────────────────────────────────
local function set_highlights()
  local function hl(name, opts)
    opts.default = true
    api.nvim_set_hl(0, name, opts)
  end
  hl("PhpTestPassed", { link = "DiagnosticOk" })
  hl("PhpTestFailed", { link = "DiagnosticError" })
  hl("PhpTestSkipped", { link = "DiagnosticWarn" })
  hl("PhpTestRunning", { link = "DiagnosticInfo" })
  hl("PhpTestNone", { link = "NonText" })
  hl("PhpTestDim", { link = "Comment" })
  -- the bars at the top are quiet: dark tints of their colour, no bold
  hl("PhpTestToggleOn", { fg = "#bfd0c6", bg = "#25352d" })
  hl("PhpTestToggleOff", { fg = "#7f858d", bg = "#24282e" })
  hl("PhpTestStepOn", { fg = "#d5e2da", bg = "#31483c" })
  hl("PhpTestStepOff", { fg = "#9aa0a8", bg = "#2c3137" })
  hl("PhpTestRun", { fg = "#b9c6da", bg = "#27334a" })
  hl("PhpTestRunFailed", { fg = "#d6bcc0", bg = "#412e32" })
  hl("PhpTestRunIdle", { fg = "#656b73", bg = "#24282e" })
end
set_highlights()
api.nvim_create_autocmd("ColorScheme", { callback = set_highlights })

local ICON = { passed = "✓", failed = "✗", skipped = "○", running = "●", none = "·" }
local STATUS_HL = {
  passed = "PhpTestPassed", failed = "PhpTestFailed", skipped = "PhpTestSkipped", running = "PhpTestRunning", none = "PhpTestNone",
}

local function status_chunk(status)
  return { ICON[status] .. " ", STATUS_HL[status] }
end

local WIDTH = 50
local HALF = WIDTH / 2 -- two buttons or toggles share a row

-- The toggles row: "  󰄵 Parallel    󰄱 Flat list", each one its own checkbox. The same table draws the row
-- and tells which one a click at a column hit.
local function toggle_parts()
  local function part(on, label, zone)
    return {
      text = "  " .. (on and "󰄵" or "󰄱") .. " " .. label .. "  ",
      hl = on and "PhpTestToggleOn" or "PhpTestToggleOff",
      zone = zone,
    }
  end
  local parts = { part(options.parallel(), "Parallel", "parallel"), part(options.flat(), "Flat list", "flat") }
  -- two halves of the row, each one fills its half
  for i, p in ipairs(parts) do
    p.text = kit.pad(p.text, HALF)
    p.from, p.to = (i - 1) * HALF + 1, i * HALF
  end
  return parts
end

--- What a click at window column `col` of the toggles row hits: "parallel" or "flat".
local function zone_at(col)
  for _, part in ipairs(toggle_parts()) do
    if col >= part.from and col <= part.to then
      return part.zone
    end
  end
  return "parallel"
end

local function format(item, picker)
  local ret = {}
  if item.kind == "progress" then
    local p = item.progress
    local width = 20
    local filled = math.floor(p.fraction * width + 0.5)
    ret[#ret + 1] = { "  ▶ ", "PhpTestRunning" }
    ret[#ret + 1] = { string.rep("█", filled), "PhpTestRunning" }
    ret[#ret + 1] = { string.rep("░", width - filled), "PhpTestNone" }
    ret[#ret + 1] = { string.format("  %d / %d", p.done, p.total), "PhpTestRunning" }
    ret[#ret + 1] = { string.format("  %d%%", math.floor(p.fraction * 100)), "PhpTestDim" }
    return ret
  end
  if item.kind == "info" then
    -- what the tests did, in words: passed, failed, skipped (a number that is 0 is dimmed), and running
    local c = item.counts
    if item.discovering then
      ret[#ret + 1] = { "  Looking for tests…", "PhpTestDim" }
    elseif c.total == 0 then
      ret[#ret + 1] = { "  No tests found", "PhpTestDim" }
    else
      ret[#ret + 1] = { "  ✓ " .. c.passed .. " passed", c.passed > 0 and "PhpTestPassed" or "PhpTestNone" }
      ret[#ret + 1] = { "   ✗ " .. c.failed .. " failed", c.failed > 0 and "PhpTestFailed" or "PhpTestNone" }
      ret[#ret + 1] = { "   ○ " .. c.skipped .. " skipped", c.skipped > 0 and "PhpTestSkipped" or "PhpTestNone" }
      if c.running > 0 then
        ret[#ret + 1] = { "   ● " .. c.running .. " running", "PhpTestRunning" }
      end
    end
    return ret
  elseif item.kind == "summary" then
    -- how many there are, and how many of them have not run yet: passed + failed + skipped + not run = all
    local c = item.counts
    if not item.discovering and c.total > 0 then
      local text = "  " .. c.total .. " tests"
      if c.total ~= item.methods then
        text = text .. " (" .. item.methods .. " methods)"
      end
      local not_run = c.total - c.passed - c.failed - c.skipped - c.running
      if not_run > 0 then
        text = text .. " · " .. not_run .. " not run yet"
      elseif c.running == 0 then
        text = text .. " · all run"
      end
      ret[#ret + 1] = { text, "PhpTestDim" }
    end
    return ret
  elseif item.kind == "toggle" then
    local width = 0
    for _, part in ipairs(toggle_parts()) do
      ret[#ret + 1] = { part.text, part.hl }
      width = width + vim.fn.strdisplaywidth(part.text)
    end
    ret[#ret + 1] = { string.rep(" ", math.max(0, WIDTH - width)), "PhpTestToggleOff" }
    return ret
  elseif item.kind == "button" then
    -- Run all | Run failed (N): two buttons, each one fills its half of the row
    local n = item.failed
    ret[#ret + 1] = { kit.pad("  ▶  Run all", HALF), "PhpTestRun" }
    ret[#ret + 1] = { kit.pad("  ✗  Run failed" .. (n > 0 and (" (" .. n .. ")") or ""), HALF), n > 0 and "PhpTestRunFailed" or "PhpTestRunIdle" }
    return ret
  end

  if item.kind == "failed" then
    ret[#ret + 1] = { (item.open and "▾" or "▸") .. " ", "PhpTestFailed" }
    ret[#ret + 1] = { "✗ Failed", "PhpTestFailed" }
    ret[#ret + 1] = { "  " .. item.count, "PhpTestDim" }
    return ret
  end
  if not item.flat then
    vim.list_extend(ret, Snacks.picker.format.tree(item, picker))
  end
  local icons = picker.opts.icons.files
  if item.kind == "dir" then
    ret[#ret + 1] = status_chunk(status_of(item.counts))
    ret[#ret + 1] = { (item.open and icons.dir_open or icons.dir) .. " ", "SnacksPickerDirectory" }
    ret[#ret + 1] = { item.text, "SnacksPickerDirectory" }
    if item.project and item.project ~= item.text then
      ret[#ret + 1] = { "  " .. item.project, "PhpTestDim" }
    end
  elseif item.kind == "file" then
    ret[#ret + 1] = status_chunk(status_of(item.counts))
    local icon, hl = Snacks.util.icon(item.text, "file")
    ret[#ret + 1] = { (icon or "") .. " ", hl }
    ret[#ret + 1] = { item.text, "SnacksPickerFile" }
    ret[#ret + 1] = { "  " .. item.counts.total, "PhpTestDim" }
  elseif item.kind == "dataset" then
    ret[#ret + 1] = status_chunk(item.status)
    -- in a list of executions the method is named too; under its method only the data set
    if item.file_name then
      ret[#ret + 1] = { item.name, item.status == "failed" and "PhpTestFailed" or nil }
      ret[#ret + 1] = { " " .. item.label, "PhpTestDim" }
      ret[#ret + 1] = { "  " .. item.file_name, "PhpTestDim" }
    else
      ret[#ret + 1] = { "with data set " .. item.label, item.status == "failed" and "PhpTestFailed" or "PhpTestDim" }
    end
  else
    if item.sets then
      ret[#ret + 1] = { require("modules.phpunit.dataset_signs").ICON[item.status] or "󰙅", STATUS_HL[item.status] }
      ret[#ret + 1] = { " ", nil }
    else
      ret[#ret + 1] = status_chunk(item.status)
    end
    ret[#ret + 1] = { item.name or item.text, item.status == "failed" and "PhpTestFailed" or nil }
    if item.sets then
      ret[#ret + 1] = { " ×" .. item.sets, "PhpTestDim" }
    end
    if item.file_name then
      ret[#ret + 1] = { "  " .. item.file_name, "PhpTestDim" }
    end
  end
  return ret
end

-- ── actions ─────────────────────────────────────────────────────────────────────────────────────
local refresh = kit.refresh

local function toggle_fold(picker, item)
  if item.kind == "dir" or item.kind == "failed" then
    collapsed[item.key] = (not collapsed[item.key]) or nil
  elseif item.kind == "test" then
    local key = "t:" .. item.id
    expanded[key] = (not expanded[key]) or nil
  else
    expanded[item.key] = (not expanded[item.key]) or nil
  end
  refresh(picker, item.key)
end

-- a test row that can be unfolded into its data sets
local function foldable(item)
  return item.kind == "dir" or item.kind == "file" or item.kind == "failed" or (item.kind == "test" and item.sets ~= nil and not item.flat and not item.file_name)
end

local function open_node(picker, item)
  if not item or not foldable(item) then
    return
  end
  if not item.open then
    if item.kind == "dir" or item.kind == "failed" then
      collapsed[item.key] = nil
    elseif item.kind == "test" then
      expanded["t:" .. item.id] = true
    else
      expanded[item.key] = true
    end
    refresh(picker, item.key)
    return
  end
  local items = picker:items()
  for index, candidate in ipairs(items) do
    if candidate.key == item.key and items[index + 1] and items[index + 1].parent == item then
      picker.list:move(index + 1, true)
      return
    end
  end
end

local function close_node(picker, item)
  if not item then
    return
  end
  if foldable(item) and item.open then
    toggle_fold(picker, item)
  elseif item.parent and item.parent.key then
    kit.move_to(picker, item.parent.key)
  end
end

local function set_all(picker, open)
  for _, file in ipairs(collect()) do
    expanded["f:" .. file.id] = open or nil
  end
  refresh(picker, (picker:current() or {}).key)
end

local function run_item(item)
  if not item then
    return
  end
  if item.kind == "failed" then
    runner().run_failed()
  elseif item.kind == "button" then
    -- (a click chooses by column: see tests_click; the keyboard runs everything)
    if item.action == "failed" then
      runner().run_failed()
    else
      runner().run_all()
    end
  elseif item.kind == "dataset" then
    -- only that data set (PHPUnit's filter), in its file
    runner().run({ item.file }, { [item.file] = { item.only_name } })
  elseif item.ids then
    runner().run(item.ids)
  end
end

local actions = {
  tests_noop = function() end,
  tests_show_search = function(picker)
    picker:toggle("input", { enable = true, focus = true })
  end,
  tests_stop_search_insert = function()
    vim.cmd("stopinsert")
  end,
  tests_clear_search = function(picker)
    picker.input:set("", "")
    picker:find()
    picker:toggle("input", { enable = false })
    picker:focus("list")
  end,
  tests_confirm = function(picker, item)
    item = item or picker:current()
    if not item then
      return
    end
    if item.kind == "toggle" then
      options.toggle_parallel()
      refresh(picker, item.key)
    elseif item.kind == "button" then
      run_item(item)
    elseif foldable(item) then
      toggle_fold(picker, item)
    elseif item.kind == "test" or item.kind == "dataset" then
      kit.goto_line(picker, item.file, item.line)
    end
  end,
  tests_jump = function(picker, item)
    item = item or picker:current()
    if item and item.file and (item.kind == "test" or item.kind == "dataset" or item.kind == "file") then
      kit.goto_line(picker, item.file, item.line or 1)
    end
  end,
  tests_run = function(picker, item)
    item = item or picker:current()
    if item and (item.kind == "toggle") then
      return
    end
    run_item(item)
  end,
  tests_all = function()
    runner().run_all()
  end,
  tests_failed = function()
    runner().run_failed()
  end,
  tests_parallel = function(picker)
    options.toggle_parallel()
    refresh(picker, "h:parallel")
  end,
  tests_view = function(picker)
    options.toggle_flat()
    refresh(picker, "h:parallel")
  end,
  tests_stop = function()
    runner().stop()
  end,
  tests_output = function(picker, item)
    item = item or picker:current()
    if item and item.ids and item.kind ~= "dir" then
      require("neotest").output.open({ position_id = item.ids[1], enter = true, short = false })
    end
  end,
  tests_open = function(picker, item)
    open_node(picker, item or picker:current())
  end,
  tests_close = function(picker, item)
    close_node(picker, item or picker:current())
  end,
  tests_expand_all = function(picker)
    set_all(picker, true)
  end,
  tests_collapse_all = function(picker)
    set_all(picker, false)
  end,
  tests_help = function()
    local lines = {
      " Tests pane keys",
      "",
      " Enter / click   open, fold, press",
      " r  Ctrl+Enter   run this row",
      " a               run all",
      " F               run failed",
      " p               parallel on/off",
      " v               flat list",
      " x               stop",
      " o               output",
      " i               jump to code",
      " l / h           open / close",
      " e / E           expand / collapse all",
      " q               close",
      " ?               this help",
    }
    Snacks.win({
      text = lines,
      width = 40,
      height = #lines,
      border = "rounded",
      backdrop = false,
      wo = { wrap = false },
      bo = { modifiable = false },
      keys = { q = "close", ["<Esc>"] = "close", ["?"] = "close" },
    })
  end,
  tests_press = kit.press,
  tests_click = function(picker)
    local mouse = vim.fn.getmousepos()
    local list_win = picker.list and picker.list.win and picker.list.win.win
    if mouse.winid ~= list_win then
      return
    end
    vim.schedule(function()
      if picker.closed then
        return
      end
      local item = picker:current()
      if item and item.kind == "toggle" then
        picker:action(zone_at(mouse.wincol) == "flat" and "tests_view" or "tests_parallel")
        return
      end
      if item and item.kind == "button" then
        run_item(vim.tbl_extend("force", item, { action = mouse.wincol > HALF and "failed" or "all" }))
        return
      end
      picker:action("tests_confirm")
    end)
  end,
}

-- ── the pane ────────────────────────────────────────────────────────────────────────────────────
--- The open panes of a tab (the current one by default).
function M.panes(tab)
  return kit.panes(SOURCE, tab)
end

local function open()
  require("neotest") -- loads neotest, which finds the tests and reports them to attach()
  if snap.sync then
    snap.sync()
  end
  require("core.sidebars").make_room("tests")
  return Snacks.picker.pick({
    source = SOURCE,
    title = "", -- the title is the winbar (kit.set_title); the search box must not repeat it
    finder = rows,
    format = format,
    tree = true,
    show_empty = true,
    focus = "list",
    auto_close = false,
    jump = { close = false },
    layout = { preset = "sidebar", preview = false, hidden = { "input" }, layout = { width = WIDTH + 4, min_width = WIDTH + 4 } },
    matcher = { sort_empty = false, fuzzy = false },
    sort = { fields = { "idx" } },
    confirm = "tests_confirm",
    actions = actions,
    on_show = function(picker)
      kit.set_title(picker, TITLE)
    end,
    win = {
      list = {
        keys = vim.tbl_extend("error", kit.mouse_keys("tests_press", "tests_click"), {
          ["<CR>"] = "tests_confirm",
          ["i"] = "tests_jump",
          ["l"] = "tests_open",
          ["h"] = "tests_close",
          ["<C-CR>"] = "tests_run",
          ["r"] = "tests_run",
          ["a"] = "tests_all",
          ["F"] = "tests_failed",
          ["p"] = "tests_parallel",
          ["v"] = "tests_view",
          ["x"] = "tests_stop",
          ["o"] = "tests_output",
          ["e"] = "tests_expand_all",
           ["E"] = "tests_collapse_all",
           ["?"] = "tests_help",
           ["/"] = "tests_show_search",
           ["q"] = "close",
           ["<Esc>"] = "tests_noop",
         }),
       },
       input = {
         keys = {
           ["<Esc>"] = { "tests_stop_search_insert", mode = { "i" } },
           ["<Esc>"] = { "tests_clear_search", mode = { "n" } },
         },
       },
     },
  })
end

--- Cmd+Shift+T: show the pane and put the cursor in it; it never closes it (Cmd+B and q do).
function M.toggle()
  require("core.leave-codediff").leave_graph()
  local panes = M.panes()
  if #panes > 0 then
    panes[1]:focus("list")
    return
  end
  open()
end

--- Cmd+B: show the pane, or hide it whatever has the focus.
function M.show_hide()
  local panes = M.panes()
  if #panes > 0 then
    for _, picker in ipairs(panes) do
      picker:close()
    end
  else
    open()
  end
end

return M
