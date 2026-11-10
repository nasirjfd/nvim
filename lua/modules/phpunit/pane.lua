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
  local function update(adapter_id)
    local tree = client:get_position(nil, { adapter = adapter_id })
    snap.adapter, snap.tree = adapter_id, tree
    snap.results = client:get_results(adapter_id) or {}
    local ok, running = pcall(function()
      return client._state:running(adapter_id)
    end)
    snap.running = ok and running or {}
    refresh_soon()
  end
  client.listeners.discover_positions = function(adapter_id)
    update(adapter_id)
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
      end
    end)
  end
  snap.sync()
end

-- ── what the keys need to know ──────────────────────────────────────────────────────────────────
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
      table.insert(only[data.path], data.name)
    end
  end
  table.sort(files)
  return only, files
end

function M.running_ids()
  return vim.tbl_keys(snap.running or {})
end

-- ── rows ────────────────────────────────────────────────────────────────────────────────────────
local function counts_of(tests)
  local c = { passed = 0, failed = 0, skipped = 0, running = 0, total = #tests }
  for _, test in ipairs(tests) do
    if snap.running[test.id] then
      c.running = c.running + 1
    else
      local result = snap.results[test.id]
      if result and c[result.status] then
        c[result.status] = c[result.status] + 1
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
    { text = "Parallel", kind = "toggle", key = "h:parallel" },
    { text = "Flat list", kind = "view", key = "h:view" },
    { text = "Run all tests", kind = "button", action = "all", key = "h:all" },
    { text = "Run failed tests", kind = "button", action = "failed", failed = total.failed, key = "h:failed" },
  }

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
      status = snap.running[test.id] and "running" or (snap.results[test.id] or {}).status or "none",
    }, extra or {})
  end

  -- flat: every test on its own row, the failed ones first
  if options.flat() then
    local list = {}
    for _, file in ipairs(files) do
      for _, test in ipairs(file.tests) do
        list[#list + 1] = test_item(test, { flat = true, file_name = vim.fs.basename(test.path) })
      end
    end
    local rank = { failed = 0, running = 1 }
    local indexed = {}
    for i, item in ipairs(list) do
      indexed[i] = { item = item, i = i }
    end
    table.sort(indexed, function(a, b)
      local ra, rb = rank[a.item.status] or 2, rank[b.item.status] or 2
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
  local failed_tests = {}
  for _, file in ipairs(files) do
    for _, test in ipairs(file.tests) do
      if not snap.running[test.id] and (snap.results[test.id] or {}).status == "failed" then
        failed_tests[#failed_tests + 1] = test
      end
    end
  end
  if #failed_tests > 0 then
    local header = {
      text = "Failed", kind = "failed", key = "x:failed", open = searching or not collapsed["x:failed"], count = #failed_tests,
    }
    items[#items + 1] = header
    if header.open then
      for i, test in ipairs(failed_tests) do
        items[#items + 1] = test_item(test, {
          key = "x:" .. test.id, parent = header, last = i == #failed_tests, file_name = vim.fs.basename(test.path),
        })
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
            items[#items + 1] = test_item(test, { text = test.name, parent = fitem, last = ti == #file.tests })
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

-- The Parallel row: "󰄵 Parallel   −  50  +  at a time". The checkbox part toggles, − and + change the
-- number; the same table draws the row and tells what a click at a column hit.
local function toggle_parts()
  local on = options.parallel()
  local bar = on and "PhpTestToggleOn" or "PhpTestToggleOff"
  local step = on and "PhpTestStepOn" or "PhpTestStepOff"
  local parts = {
    { text = "  " .. (on and "󰄵" or "󰄱") .. "  Parallel", hl = bar, zone = "toggle" },
    { text = "    ", hl = bar, zone = "toggle" },
    { text = " − ", hl = step, zone = "minus" },
    { text = " " .. options.workers() .. " ", hl = bar, zone = "count" },
    { text = " + ", hl = step, zone = "plus" },
    { text = " at a time", hl = bar, zone = "toggle" },
  }
  local col = 1
  for _, part in ipairs(parts) do
    part.from, part.to = col, col + vim.fn.strdisplaywidth(part.text) - 1
    col = part.to + 1
  end
  return parts
end

--- What a click at window column `col` of the Parallel row hits: "minus", "plus" or "toggle".
local function zone_at(col)
  for _, part in ipairs(toggle_parts()) do
    if col >= part.from and col <= part.to then
      return (part.zone == "count") and "toggle" or part.zone
    end
  end
  return "toggle"
end

local function format(item, picker)
  local ret = {}
  if item.kind == "info" then
    local c = item.counts
    if item.discovering then
      ret[#ret + 1] = { "  Looking for tests…", "PhpTestDim" }
    elseif c.total == 0 then
      ret[#ret + 1] = { "  No tests found", "PhpTestDim" }
    else
      ret[#ret + 1] = { "  ✓ " .. c.passed, "PhpTestPassed" }
      ret[#ret + 1] = { "   ✗ " .. c.failed, c.failed > 0 and "PhpTestFailed" or "PhpTestNone" }
      ret[#ret + 1] = { "   ○ " .. c.skipped, c.skipped > 0 and "PhpTestSkipped" or "PhpTestNone" }
      if c.running > 0 then
        ret[#ret + 1] = { "   ● " .. c.running, "PhpTestRunning" }
      end
      ret[#ret + 1] = { "   " .. c.total .. " tests", "PhpTestDim" }
    end
    return ret
  elseif item.kind == "toggle" then
    local width = 0
    for _, part in ipairs(toggle_parts()) do
      ret[#ret + 1] = { part.text, part.hl }
      width = width + vim.fn.strdisplaywidth(part.text)
    end
    local on = options.parallel()
    ret[#ret + 1] = { string.rep(" ", math.max(0, WIDTH - width)), on and "PhpTestToggleOn" or "PhpTestToggleOff" }
    return ret
  elseif item.kind == "view" then
    local on = options.flat()
    ret[#ret + 1] = {
      kit.pad("  " .. (on and "󰄵" or "󰄱") .. "  Flat list of all tests", WIDTH),
      on and "PhpTestToggleOn" or "PhpTestToggleOff",
    }
    return ret
  elseif item.kind == "button" then
    if item.action == "all" then
      ret[#ret + 1] = { kit.pad("  ▶  Run all tests", WIDTH), "PhpTestRun" }
    else
      local n = item.failed
      ret[#ret + 1] = { kit.pad("  ✗  Run failed tests" .. (n > 0 and (" (" .. n .. ")") or ""), WIDTH), n > 0 and "PhpTestRunFailed" or "PhpTestRunIdle" }
    end
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
  else
    ret[#ret + 1] = status_chunk(item.status)
    ret[#ret + 1] = { item.name or item.text, item.status == "failed" and "PhpTestFailed" or nil }
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
  else
    expanded[item.key] = (not expanded[item.key]) or nil
  end
  refresh(picker, item.key)
end

local function open_node(picker, item)
  if not item or (item.kind ~= "dir" and item.kind ~= "file" and item.kind ~= "failed") then
    return
  end
  if not item.open then
    if item.kind == "dir" or item.kind == "failed" then
      collapsed[item.key] = nil
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
  if (item.kind == "dir" or item.kind == "file" or item.kind == "failed") and item.open then
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
    if item.action == "all" then
      runner().run_all()
    else
      runner().run_failed()
    end
  elseif item.ids then
    runner().run(item.ids)
  end
end

local actions = {
  tests_confirm = function(picker, item)
    item = item or picker:current()
    if not item then
      return
    end
    if item.kind == "toggle" then
      options.toggle_parallel()
      refresh(picker, item.key)
    elseif item.kind == "view" then
      options.toggle_flat()
      refresh(picker, item.key)
    elseif item.kind == "button" then
      run_item(item)
    elseif item.kind == "test" then
      kit.goto_line(picker, item.file, item.line)
    elseif item.kind == "dir" or item.kind == "file" or item.kind == "failed" then
      toggle_fold(picker, item)
    end
  end,
  tests_run = function(picker, item)
    item = item or picker:current()
    if item and (item.kind == "toggle" or item.kind == "view") then
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
    refresh(picker, "h:view")
  end,
  tests_more = function(picker)
    options.set_workers(options.workers() + options.step(true))
    refresh(picker, "h:parallel")
  end,
  tests_less = function(picker)
    options.set_workers(options.workers() - options.step(false))
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
        local zone = zone_at(mouse.wincol)
        if zone == "minus" then
          picker:action("tests_less")
        elseif zone == "plus" then
          picker:action("tests_more")
        else
          picker:action("tests_parallel")
        end
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
          ["l"] = "tests_open",
          ["h"] = "tests_close",
          ["<C-CR>"] = "tests_run",
          ["r"] = "tests_run",
          ["a"] = "tests_all",
          ["F"] = "tests_failed",
          ["p"] = "tests_parallel",
          ["v"] = "tests_view",
          ["+"] = "tests_more",
          ["="] = "tests_more",
          ["<kPlus>"] = "tests_more",
          ["-"] = "tests_less",
          ["<kMinus>"] = "tests_less",
          ["x"] = "tests_stop",
          ["o"] = "tests_output",
          ["e"] = "tests_expand_all",
          ["E"] = "tests_collapse_all",
          ["q"] = "close",
          ["<Esc>"] = "close",
        }),
      },
    },
  })
end

--- Cmd+Shift+T: show the pane; focus it when it is open elsewhere; close it when it has the focus.
function M.toggle()
  local panes = M.panes()
  if #panes > 0 then
    local current = api.nvim_get_current_win()
    for _, picker in ipairs(panes) do
      if picker.list.win.win == current then
        picker:close()
      else
        picker:focus("list")
      end
    end
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
