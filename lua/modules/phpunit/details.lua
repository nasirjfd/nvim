-- The failure view of a test, like an IDE's test runner: a window at the bottom of the editor with everything about
-- one test's last run, every part of it a link.
--
--   ✗ BTest::testTwo with data set #1 (false)          the test (Enter: its definition)
--     BTest.php:9 · 12 ms · ExpectationFailedException where it failed (Enter: that line), how long it took
--     Failed asserting that two strings are identical. the message (a "file.php:N" in it is a link too)
--     --- Expected / +++ Actual / -'a' / +'b'          the comparison, coloured (d: side by side in a diff tab)
--     Stack trace                                      innermost first: the project's frames bright,
--     → src/Foo.php:20                                 dependencies dim (Enter: that line)
--     Output                                           what the test printed
--
-- Also: ]f / [f go from failure to failure (in every file), <leader>td shows the failure under the cursor,
-- <leader>tq lists every failure in the quickfix list, and the line of the project's code where an exception was
-- thrown gets a mark ("↳ RuntimeException: boom · thrown in BTest::testTwo"), even outside the test files.
local failure = require("modules.phpunit.failure")
local plan = require("modules.phpunit.plan")

local M = {}

local api = vim.api
local ns = api.nvim_create_namespace("phpunit_details")
local origin_ns = api.nvim_create_namespace("phpunit_origins")
local NAME = "phpunit://test-failure"

local state = {
  buf = nil, ---@type integer?
  win = nil, ---@type integer?
  editor = nil, ---@type integer? the window files are opened in
  entry = nil, ---@type table? what is shown
  targets = {}, ---@type table<integer, { file: string, line: integer }> line of the view -> where Enter goes
}

local function set_highlights()
  local function hl(name, link)
    api.nvim_set_hl(0, name, { link = link, default = true })
  end
  hl("PhpFailTitle", "DiagnosticError")
  hl("PhpPassTitle", "DiagnosticOk")
  hl("PhpSkipTitle", "DiagnosticWarn")
  hl("PhpFailMessage", "DiagnosticError")
  hl("PhpFailDim", "Comment")
  hl("PhpFailSection", "Title")
  hl("PhpFailFrame", "Directory")
  hl("PhpFailFrameVendor", "Comment")
  hl("PhpFailLink", "Underlined")
  hl("PhpFailExpected", "Removed")
  hl("PhpFailActual", "Added")
  hl("PhpFailOrigin", "DiagnosticVirtualTextError")
end
set_highlights()
api.nvim_create_autocmd("ColorScheme", { callback = set_highlights })

local function root()
  local configured = plan.is_configured() and plan.get().root
  if configured then
    return configured
  end
  local pane = package.loaded["modules.phpunit.pane"]
  return pane and pane.root_id() or vim.uv.cwd()
end

--- A path for people: relative to the project when it is in it.
local function show_path(file)
  local base = root()
  if base and file:sub(1, #base + 1) == base .. "/" then
    return file:sub(#base + 2)
  end
  return vim.fn.fnamemodify(file, ":~")
end

-- ── what there is to show ───────────────────────────────────────────────────────────────────────
-- One test (or one data set of it) and its last result, ready to show.
local function entry_of(data, result, set)
  local src = set or result
  local message = src.message
    or (src.errors and src.errors[1] and src.errors[1].message)
    or (src.status == "failed" and src.short)
    or ""
  local parsed = failure.parse(message, { root = root() })
  local test_line = data.range and (data.range[1] + 1) or 1
  local line = failure.test_line(parsed, data.path)
    or (src.errors and src.errors[1] and src.errors[1].line and (src.errors[1].line + 1))
    or test_line
  return {
    key = data.id .. (set and ("\0" .. set.label) or ""),
    id = data.id,
    name = data.name,
    label = set and set.label or nil,
    file = data.path,
    test_line = test_line,
    line = line,
    status = src.status,
    message = message,
    parsed = parsed,
    exception = src.exception,
    time = src.time,
    stdout = src.stdout or (not set and result.stdout) or nil,
    short = src.short,
  }
end

local function snapshot()
  local pane = require("modules.phpunit.pane")
  pane.sync_results()
  return pane.snapshot()
end

--- Every failure of the last runs, in file order then line order: one per failed test, or per failed data set.
function M.failures()
  local snap = snapshot()
  local list = {}
  if not snap.tree then
    return list
  end
  for _, node in snap.tree:iter_nodes() do
    local data = node:data()
    local result = data.type == "test" and snap.results[data.id]
    if result and result.status == "failed" then
      local any = false
      for _, set in ipairs(result.datasets or {}) do
        if set.status == "failed" then
          list[#list + 1] = entry_of(data, result, set)
          any = true
        end
      end
      if not any then
        list[#list + 1] = entry_of(data, result)
      end
    end
  end
  table.sort(list, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    if a.line ~= b.line then
      return a.line < b.line
    end
    return a.key < b.key
  end)
  return list
end

--- The entry of a test (any status), or of one of its data sets.
function M.entry(id, label)
  local snap = snapshot()
  local node = snap.tree and snap.tree:get_key(id)
  local result = snap.results[id] or require("modules.phpunit.pane").last_result(id)
  if not (node and result) then
    return nil
  end
  local data = node:data()
  if data.type ~= "test" then
    -- a file or folder: its first failure
    for _, e in ipairs(M.failures()) do
      if e.id == id or e.file:sub(1, #id + 1) == id .. "/" or e.file == id then
        return e
      end
    end
    return nil
  end
  if label then
    for _, set in ipairs(result.datasets or {}) do
      if set.label == label then
        return entry_of(data, result, set)
      end
    end
  end
  -- a method with data sets and no label: the first one that failed
  for _, set in ipairs(result.datasets or {}) do
    if set.status == "failed" then
      return entry_of(data, result, set)
    end
  end
  return entry_of(data, result)
end

-- ── the view ────────────────────────────────────────────────────────────────────────────────────
local ICON = { failed = "✗", passed = "✓", skipped = "○" }
local TITLE_HL = { failed = "PhpFailTitle", passed = "PhpPassTitle", skipped = "PhpSkipTitle" }

--- The lines of the view of `entry`, their highlights ({ row, col, end_col, group }) and links (row -> place).
function M.build(entry)
  local lines, marks, targets = {}, {}, {}
  local function add(text, group, target)
    lines[#lines + 1] = text
    if group then
      marks[#marks + 1] = { #lines - 1, 0, #text, group }
    end
    if target then
      targets[#lines] = target
    end
  end
  local function blank()
    if lines[#lines] ~= "" then
      lines[#lines + 1] = ""
    end
  end
  local parsed = entry.parsed
  local title = parsed.title
  if not title then
    local class = vim.fn.fnamemodify(entry.file, ":t:r")
    title = class
      .. "::"
      .. entry.name
      .. (entry.label and (" with data set " .. entry.label) or "")
  end
  add(
    " " .. (ICON[entry.status] or "●") .. " " .. title,
    TITLE_HL[entry.status] or "PhpFailDim",
    {
      file = entry.file,
      line = entry.test_line,
    }
  )
  local meta = { vim.fs.basename(entry.file) .. ":" .. entry.line }
  if entry.time then
    meta[#meta + 1] = failure.duration(entry.time)
  end
  if entry.exception then
    meta[#meta + 1] = entry.exception
  end
  add("   " .. table.concat(meta, " · "), "PhpFailDim", { file = entry.file, line = entry.line })

  if entry.status == "failed" then
    blank()
    for _, line in ipairs(parsed.lines) do
      local file, n = line:match("(/[^%s:\"']+%.php):(%d+)")
      local text = "   " .. line
      add(text, line:match("^Caused by") and "PhpFailSection" or "PhpFailMessage", file and {
        file = file,
        line = tonumber(n),
      } or nil)
    end
    if parsed.diff then
      blank()
      add("   Expected ↔ Actual  (d: side by side)", "PhpFailSection")
      for _, line in ipairs(parsed.diff) do
        local mark = line:sub(1, 1)
        local group = (mark == "-" and "PhpFailExpected")
          or (mark == "+" and "PhpFailActual")
          or (mark == "@" and "PhpFailDim")
          or nil
        add("   " .. line, group)
      end
    elseif parsed.expected then
      blank()
      add("   Expected: " .. parsed.expected, "PhpFailExpected")
      add("   Actual:   " .. parsed.actual, "PhpFailActual")
    end
    if #parsed.frames > 0 then
      blank()
      add("   Stack trace", "PhpFailSection")
      local origin = failure.origin(parsed, entry.file)
      for _, frame in ipairs(parsed.frames) do
        local here = (origin and frame == origin)
          or (not origin and frame.file == entry.file and frame.line == entry.line)
        local text = (here and "   → " or "     ") .. show_path(frame.file) .. ":" .. frame.line
        add(
          text,
          frame.project and "PhpFailFrame" or "PhpFailFrameVendor",
          { file = frame.file, line = frame.line }
        )
      end
    end
  elseif entry.status == "skipped" then
    blank()
    add(
      "   Skipped"
        .. (
          (entry.short and entry.short ~= "" and entry.short ~= "not run")
            and (": " .. entry.short)
          or ""
        ),
      "PhpFailDim"
    )
  else
    blank()
    add("   Passed", "PhpPassTitle")
  end

  if entry.stdout and vim.trim(entry.stdout) ~= "" then
    blank()
    add("   Output", "PhpFailSection")
    for line in (entry.stdout:gsub("\n+$", "") .. "\n"):gmatch("([^\n]*)\n") do
      add("   " .. line)
    end
  end
  return lines, marks, targets
end

local function normal_window(win)
  if not (win and api.nvim_win_is_valid(win)) or win == state.win then
    return false
  end
  if api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local buf = api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and not vim.bo[buf].filetype:match("^snacks")
end

--- The window files open in: the last editor window of this tab.
local function editor_window()
  local tab = api.nvim_get_current_tabpage()
  if normal_window(state.editor) and api.nvim_win_get_tabpage(state.editor) == tab then
    return state.editor
  end
  for _, win in ipairs({ api.nvim_get_current_win(), vim.fn.win_getid(vim.fn.winnr("#")) }) do
    if normal_window(win) then
      state.editor = win
      return win
    end
  end
  local best, size
  for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
    if normal_window(win) then
      local s = api.nvim_win_get_width(win) * api.nvim_win_get_height(win)
      if not size or s > size then
        best, size = win, s
      end
    end
  end
  state.editor = best
  return best
end

--- Show `line` of `file` in the editor window; the cursor goes there unless `stay`.
function M.jump(file, line, stay)
  local from = api.nvim_get_current_win()
  local win = editor_window()
  if not win then
    vim.cmd("aboveleft new")
    win = api.nvim_get_current_win()
    state.editor = win
  end
  api.nvim_set_current_win(win)
  if plan.norm(api.nvim_buf_get_name(0)) ~= plan.norm(file) then
    vim.cmd("edit " .. vim.fn.fnameescape(file))
  end
  pcall(
    api.nvim_win_set_cursor,
    win,
    { math.max(1, math.min(line, api.nvim_buf_line_count(0))), 0 }
  )
  vim.cmd("normal! zz")
  if stay and api.nvim_win_is_valid(from) then
    api.nvim_set_current_win(from)
  end
end

function M.is_open()
  return state.win ~= nil and api.nvim_win_is_valid(state.win)
end

local function index_of(list, entry)
  for i, e in ipairs(list) do
    if entry and e.key == entry.key then
      return i
    end
  end
end

local function winbar(entry)
  local list = M.failures()
  local i = index_of(list, entry)
  local where = i and string.format("Failure %d/%d", i, #list)
    or (#list > 0 and (#list .. " failed") or "Test")
  return "%#PhpFailSection# "
    .. where
    .. " %#PhpFailDim#  Enter go to · d diff · r run again · y copy · o output · ]f [f next/prev · q close"
end

local actions = {}

local function setup_buffer()
  if state.buf and api.nvim_buf_is_valid(state.buf) then
    return state.buf
  end
  local buf = api.nvim_create_buf(false, true)
  state.buf = buf
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  pcall(api.nvim_buf_set_name, buf, NAME)
  vim.bo[buf].filetype = "phpunit_failure"
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map("<CR>", actions.follow_link, "Go to the place on this line")
  map("gf", actions.follow_link, "Go to the place on this line")
  map("<2-LeftMouse>", actions.follow_link, "Go to the place on this line")
  map("<Tab>", function()
    actions.next_link(1)
  end, "Next link")
  map("<S-Tab>", function()
    actions.next_link(-1)
  end, "Previous link")
  map("d", actions.diff, "Expected and actual side by side")
  map("r", actions.rerun, "Run this test again")
  map("y", actions.copy, "Copy the failure")
  map("o", actions.output, "The whole output of the run")
  map("]f", function()
    M.next_failure(1)
  end, "Next failed test")
  map("[f", function()
    M.next_failure(-1)
  end, "Previous failed test")
  map("q", M.close, "Close")
  return buf
end

--- Draw `entry` in the view (opening it when `open`); nothing when the view is closed and not `open`.
function M.render(entry, open)
  if not entry then
    return
  end
  if not M.is_open() and not open then
    return
  end
  local buf = setup_buffer()
  local lines, marks, targets = M.build(entry)
  local same = state.entry and state.entry.key == entry.key
  state.entry, state.targets = entry, targets
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    pcall(api.nvim_buf_set_extmark, buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
  for row in pairs(targets) do
    -- the path of a frame is underlined: it is a link
    local text = lines[row]
    local s, e = text:find("[^%s→]+:%d+")
    if s then
      pcall(
        api.nvim_buf_set_extmark,
        buf,
        ns,
        row - 1,
        s - 1,
        { end_col = e, hl_group = "PhpFailLink", priority = 200 }
      )
    end
  end
  if not M.is_open() then
    local editor = editor_window()
    local height = math.max(8, math.min(#lines + 1, math.floor(vim.o.lines * 0.4)))
    state.win = api.nvim_open_win(
      buf,
      false,
      editor and { split = "below", win = editor, height = height }
        or { split = "below", win = -1, height = height }
    )
    local wo = vim.wo[state.win]
    wo.number, wo.relativenumber, wo.signcolumn, wo.foldcolumn = false, false, "no", "0"
    wo.wrap, wo.linebreak, wo.cursorline, wo.spell, wo.list = true, true, true, false, false
    wo.winfixheight = true
    wo.statuscolumn = ""
  end
  vim.wo[state.win].winbar = winbar(entry)
  if not same then
    pcall(api.nvim_win_set_cursor, state.win, { 1, 0 })
  end
end

--- Open the view on `entry` and put the cursor in it.
function M.open(entry)
  if not entry then
    vim.notify(
      "No result for this test yet: run it first",
      vim.log.levels.INFO,
      { title = "Tests" }
    )
    return
  end
  M.render(entry, true)
  api.nvim_set_current_win(state.win)
end

function M.close()
  if M.is_open() then
    pcall(api.nvim_win_close, state.win, true)
  end
  state.win = nil
end

--- What is shown now (for tests).
function M.current()
  return state.entry
end

-- ── the keys of the view ────────────────────────────────────────────────────────────────────────
function actions.follow_link()
  local row = api.nvim_win_get_cursor(0)[1]
  local target = state.targets[row]
  if target then
    M.jump(target.file, target.line)
  end
end

function actions.next_link(step)
  local row = api.nvim_win_get_cursor(0)[1]
  local count = api.nvim_buf_line_count(0)
  for i = 1, count do
    local r = ((row - 1 + step * i) % count) + 1
    if state.targets[r] then
      api.nvim_win_set_cursor(0, { r, 0 })
      return
    end
  end
end

--- Expected and actual in a tab of their own, side by side as a diff.
function M.diff(entry)
  entry = entry or state.entry
  if not (entry and entry.parsed.expected) then
    vim.notify("This failure compares no values", vim.log.levels.INFO, { title = "Tests" })
    return
  end
  vim.cmd("tabnew")
  local tab = api.nvim_get_current_tabpage()
  local n = tab
  local function side(win, name, text)
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    pcall(api.nvim_buf_set_name, buf, ("phpunit://%s/%d"):format(name:lower(), n))
    api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
    vim.bo[buf].modifiable = false
    api.nvim_win_set_buf(win, buf)
    vim.wo[win].winbar = "%#PhpFailSection# " .. name
    api.nvim_win_call(win, function()
      vim.cmd("diffthis")
    end)
    vim.keymap.set("n", "q", function()
      if api.nvim_tabpage_is_valid(tab) then
        vim.cmd("tabclose " .. api.nvim_tabpage_get_number(tab))
      end
    end, { buffer = buf, nowait = true, desc = "Close the comparison" })
  end
  local left = api.nvim_get_current_win()
  local scratch = api.nvim_get_current_buf()
  vim.cmd("rightbelow vsplit")
  local right = api.nvim_get_current_win()
  side(left, "Expected", entry.parsed.expected)
  side(right, "Actual", entry.parsed.actual)
  if api.nvim_buf_is_valid(scratch) and scratch ~= api.nvim_win_get_buf(left) then
    pcall(api.nvim_buf_delete, scratch, { force = true })
  end
end
actions.diff = function()
  M.diff()
end

--- Run the shown test (or data set) again.
function actions.rerun()
  local e = state.entry
  if not e then
    return
  end
  local runner = require("modules.phpunit.runner")
  if e.label then
    runner.run({ e.file }, { [e.file] = { e.name .. " with data set " .. e.label } })
  else
    runner.run({ e.id })
  end
end

--- The failure as text: the test, the message, the trace, the output (for a bug report or a chat).
function M.text(entry)
  local lines = M.build(entry)
  return table.concat(lines, "\n")
end

function actions.copy()
  if not state.entry then
    return
  end
  local text = M.text(state.entry)
  vim.fn.setreg('"', text)
  pcall(vim.fn.setreg, "+", text)
  vim.notify("Copied the failure of " .. state.entry.name, vim.log.levels.INFO, { title = "Tests" })
end

function actions.output()
  if state.entry then
    require("neotest").output.open({ position_id = state.entry.id, enter = true, short = false })
  end
end

-- ── from the code ───────────────────────────────────────────────────────────────────────────────
--- ]f / [f: the next / previous failure, in every file. From the view it shows that failure (the cursor stays in the
--- view, the editor follows); from a file the cursor goes to the line that failed.
function M.next_failure(step)
  local list = M.failures()
  if #list == 0 then
    vim.notify("No failed tests", vim.log.levels.INFO, { title = "Tests" })
    return
  end
  local target
  local in_view = api.nvim_get_current_win() == state.win
  local i = in_view and index_of(list, state.entry)
  if i then
    target = list[((i - 1 + step) % #list) + 1]
  else
    local file = plan.norm(api.nvim_buf_get_name(0))
    local row = api.nvim_win_get_cursor(0)[1]
    local function after(e)
      return e.file > file or (e.file == file and e.line > row)
    end
    local function before(e)
      return e.file < file or (e.file == file and e.line < row)
    end
    if step > 0 then
      for _, e in ipairs(list) do
        if after(e) then
          target = e
          break
        end
      end
      target = target or list[1]
    else
      for k = #list, 1, -1 do
        if before(list[k]) then
          target = list[k]
          break
        end
      end
      target = target or list[#list]
    end
  end
  M.jump(target.file, target.line, in_view)
  M.render(target)
  local at = index_of(list, target)
  vim.api.nvim_echo(
    {
      { string.format("Failure %d/%d: ", at, #list), "PhpFailDim" },
      {
        (target.parsed.lines[1] or target.short or ""):sub(1, math.max(10, vim.o.columns - 30)),
        "PhpFailMessage",
      },
    },
    false,
    {}
  )
end

--- <leader>td: the failure on the cursor's line, else the one of the test the cursor is in, else of the code line an
--- exception was thrown from, else the first failure of the file, else the first one.
function M.show_at_cursor()
  if api.nvim_get_current_win() == state.win then
    return
  end
  local list = M.failures()
  local file = plan.norm(api.nvim_buf_get_name(0))
  local row = api.nvim_win_get_cursor(0)[1]
  state.editor = normal_window(api.nvim_get_current_win()) and api.nvim_get_current_win()
    or state.editor
  for _, e in ipairs(list) do
    if e.file == file and e.line == row then
      return M.open(e)
    end
  end
  local pane = require("modules.phpunit.pane")
  local id = pane.nearest(file, row - 1)
  if id and id ~= file then
    local e = M.entry(id)
    if e then
      return M.open(e)
    end
  end
  for _, e in ipairs(list) do
    local origin = failure.origin(e.parsed, e.file)
    if origin and origin.file == file and origin.line == row then
      return M.open(e)
    end
  end
  for _, e in ipairs(list) do
    if e.file == file then
      return M.open(e)
    end
  end
  if list[1] then
    return M.open(list[1])
  end
  vim.notify("No failed tests", vim.log.levels.INFO, { title = "Tests" })
end

--- <leader>tq: every failure in the quickfix list: where the test failed, and where an exception came from.
function M.quickfix()
  local items = {}
  for _, e in ipairs(M.failures()) do
    local name = vim.fn.fnamemodify(e.file, ":t:r")
      .. "::"
      .. e.name
      .. (e.label and (" " .. e.label) or "")
    local first = e.parsed.lines[1] or e.short or "failed"
    items[#items + 1] =
      { filename = e.file, lnum = e.line, text = name .. ": " .. first, type = "E" }
    local origin = failure.origin(e.parsed, e.file)
    if origin then
      items[#items + 1] = {
        filename = origin.file,
        lnum = origin.line,
        text = "  thrown here for " .. name,
        type = "I",
      }
    end
  end
  if #items == 0 then
    vim.notify("No failed tests", vim.log.levels.INFO, { title = "Tests" })
    return
  end
  vim.fn.setqflist({}, " ", { title = "Failed tests", items = items })
  vim.cmd("botright copen")
end

-- ── where exceptions were thrown ────────────────────────────────────────────────────────────────
local origins = {} ---@type table<string, { line: integer, text: string, tests: string[] }[]>

local function render_origins(buf)
  if not api.nvim_buf_is_valid(buf) or not api.nvim_buf_is_loaded(buf) then
    return
  end
  api.nvim_buf_clear_namespace(buf, origin_ns, 0, -1)
  local name = api.nvim_buf_get_name(buf)
  if name == "" then
    return
  end
  local count = api.nvim_buf_line_count(buf)
  for _, o in ipairs(origins[plan.norm(name)] or {}) do
    if o.line <= count then
      local who = #o.tests == 1 and o.tests[1] or (#o.tests .. " tests")
      pcall(api.nvim_buf_set_extmark, buf, origin_ns, o.line - 1, 0, {
        sign_text = "󱐋",
        sign_hl_group = "DiagnosticSignError",
        virt_lines = {
          { { "  ↳ " .. o.text .. " · thrown in " .. who .. "  (<leader>td)", "PhpFailOrigin" } },
        },
        priority = 1050,
      })
    end
  end
end

--- Rebuild the marks of the places exceptions came from (after a run).
function M.refresh_origins()
  local before = origins
  origins = {}
  for _, e in ipairs(M.failures()) do
    local origin = failure.origin(e.parsed, e.file)
    if origin then
      local list = origins[origin.file] or {}
      origins[origin.file] = list
      local found
      for _, o in ipairs(list) do
        if o.line == origin.line then
          found = o
        end
      end
      local test = vim.fn.fnamemodify(e.file, ":t:r") .. "::" .. e.name
      if found then
        if not vim.tbl_contains(found.tests, test) then
          table.insert(found.tests, test)
        end
      else
        list[#list + 1] = {
          line = origin.line,
          text = e.parsed.lines[1] or e.exception or "failed",
          tests = { test },
        }
      end
    end
  end
  for _, buf in ipairs(api.nvim_list_bufs()) do
    local name = api.nvim_buf_is_loaded(buf) and plan.norm(api.nvim_buf_get_name(buf))
    if name and (origins[name] or before[name]) then
      render_origins(buf)
    end
  end
end

api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter" }, {
  group = api.nvim_create_augroup("phpunit_origins", { clear = true }),
  callback = function(args)
    if next(origins) then
      render_origins(args.buf)
    end
  end,
})

--- After new results: the view shows the new result of its test, the marks follow.
function M.on_results()
  M.refresh_origins()
  if M.is_open() and state.entry then
    local fresh = M.entry(state.entry.id, state.entry.label)
    if fresh then
      M.render(fresh)
    end
  end
end

M.namespace, M.origin_namespace = ns, origin_ns

return M
