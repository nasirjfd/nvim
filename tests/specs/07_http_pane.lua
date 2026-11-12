-- The HTTP Requests pane (<leader>h): parsing, curl conversion, and the pane on a real screen.
local lib = require("lib")
local h = require("support")
local parse = require("modules.http_requests.parse").parse

-- ── parse (pure) ────────────────────────────────────────────────────────────────────────────────
lib.test("http parse: names come from @name, then ###, then METHOD url", function()
  local r = parse({
    "### List users", "GET https://x/users", "",
    "### Create", "# @name make-user", "POST https://x/users", "",
    "###", "DELETE https://x/users/1",
  })
  lib.eq(3, #r)
  lib.eq({ "List users", "GET", "https://x/users", 2 }, { r[1].name, r[1].method, r[1].url, r[1].line })
  lib.eq({ "make-user", "POST", 6 }, { r[2].name, r[2].method, r[2].line })
  lib.eq({ "DELETE https://x/users/1", "DELETE", 9 }, { r[3].name, r[3].method, r[3].line })
  lib.eq({ 1, 3 }, { r[1].start_line, r[1].end_line })
  lib.eq({ 4, 7 }, { r[2].start_line, r[2].end_line })
end)

lib.test("http parse: a file without ### is one request; comments and variables before the request line are skipped", function()
  local r = parse({ "@host = https://x", "# a comment", "// another", "GET {{host}}/a HTTP/1.1", "Accept: */*" })
  lib.eq(1, #r)
  lib.eq({ "GET", "{{host}}/a", 4 }, { r[1].method, r[1].url, r[1].line })
end)

lib.test("http parse: blocks without a request line are not requests; empty input gives none", function()
  lib.eq(0, #parse({}))
  lib.eq(0, #parse({ "", "### only a title", "# just a note" }))
  lib.eq(1, #parse({ "### note", "", "### real", "GET https://x" }))
  lib.eq(0, #parse({ "### x", "Not a method line" }))
end)

lib.test("http parse: any known method counts, an unknown word does not", function()
  local r = parse({ "### a", "PATCH https://x", "### b", "OPTIONS https://x", "### c", "FETCH https://x" })
  lib.eq({ "PATCH", "OPTIONS" }, { r[1].method, r[2].method })
  lib.eq(2, #r)
end)

-- ── the project used by the screen tests ────────────────────────────────────────────────────────
local USERS = {
  "### List users", "GET https://example.com/users", "Accept: application/json", "",
  "### Create user", "# @name make-user", "POST https://example.com/users", "", "{\"a\":1}", "",
  "###", "DELETE https://example.com/users/1",
}

local function project()
  local dir = h.tmpdir()
  h.write(dir .. "/api/users/users.http", USERS)
  h.write(dir .. "/api/health.http", { "GET https://example.com/health" })
  h.write(dir .. "/auth/login.http", { "### Login", "POST https://example.com/login" })
  h.write(dir .. "/notes.txt", { "not http" })
  return dir
end

local function open_pane(dir)
  local screen = h.nvim(dir)
  h.wait(screen, function()
    return screen:exec("return package.loaded['kulala'] ~= nil")
  end, "kulala did not load")
  -- what the tests need from the outside world: a fake clipboard (never the real one), notifications, and a
  -- Kulala that does not send anything
  screen:exec([[
    _G.clip = ""
    require("modules.http_requests").clipboard = function() return _G.clip end
    _G.notes = {}
    vim.notify = function(message, level) table.insert(_G.notes, { message, level }) end
    _G.runs = {}
    require("kulala").run = function() table.insert(_G.runs, { vim.api.nvim_buf_get_name(0), vim.api.nvim_win_get_cursor(0)[1] }) end
  ]])
  screen:input("<Space>h")
  h.wait(screen, function()
    return screen:exec("return #require('modules.http_requests').panes() == 1")
  end, "the pane never opened")
  h.wait(screen, function()
    return h.find_on_screen(screen, "make-user") ~= nil
  end, "the requests are not on the screen")
  return screen
end

local function where(screen)
  return screen:exec("return { vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t'), vim.api.nvim_win_get_cursor(0)[1] }")
end

-- (the pane is the 40 left columns; the file next to it may show the same words)
local function click_on(screen, text)
  local row, col = h.find_on_screen(screen, text, 40)
  lib.ok(row, "'" .. text .. "' is not on the screen")
  h.click(screen, row, col + 1)
end

-- click a request and wait until its file is open (the click acts on the next loop iteration)
local function click_request(screen, text, file)
  click_on(screen, text)
  h.wait(screen, function()
    return where(screen)[1] == file
  end, "clicking '" .. text .. "' did not open " .. file)
end

-- the toolbar icons of the pane (new request, request from the clipboard curl, hidden folders)
local ICON = { new = "\u{F0415}", curl = "\u{F014D}", hidden = "\u{F0209}", hidden_on = "\u{F0208}" }

local function click_tool(screen, name)
  local row, col = h.find_on_screen(screen, ICON[name], 40)
  lib.ok(row, "the " .. name .. " icon is not on the screen")
  h.click(screen, row, col)
end

local function focus_pane(screen)
  if screen:exec("return vim.bo.filetype") ~= "snacks_picker_list" then
    screen:input("<Space>h")
  end
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'snacks_picker_list'")
  end, "the pane did not get the focus")
end

lib.test("http pane: shows folders, files and their requests; folders and files fold", function()
  local screen = open_pane(project())
  for _, text in ipairs({ ICON.new, ICON.curl, ICON.hidden, "api", "users", "users.http", "List users", "make-user", "health.http", "auth", "login.http", "Login" }) do
    lib.ok(h.find_on_screen(screen, text), "'" .. text .. "' is missing from the pane")
  end
  lib.ok(not h.find_on_screen(screen, "notes.txt"), "a non-http file is listed")
  -- GET / POST badges
  lib.ok(h.find_on_screen(screen, " GET "), "no GET badge")
  lib.ok(h.find_on_screen(screen, " POST "), "no POST badge")
  click_on(screen, "auth") -- fold the folder
  h.wait(screen, function()
    return not h.find_on_screen(screen, "login.http")
  end, "the folder did not fold")
  lib.ok(h.find_on_screen(screen, "users.http"), "folding one folder hid another")
  click_on(screen, "auth") -- and open it again
  h.wait(screen, function()
    return h.find_on_screen(screen, "login.http") ~= nil
  end, "the folder did not open again")
  screen:close()
end)

lib.test("http pane: clicking a request goes to it in its file", function()
  local screen = open_pane(project())
  click_on(screen, "make-user")
  h.wait(screen, function()
    return where(screen)[1] == "users.http"
  end, "the file did not open")
  lib.eq({ "users.http", 7 }, where(screen), "the cursor must be on the request line (POST …)")
  click_on(screen, "Login")
  h.wait(screen, function()
    return where(screen)[1] == "login.http"
  end, "the second file did not open")
  lib.eq({ "login.http", 2 }, where(screen))
  screen:close()
end)

lib.test("http pane: Ctrl+Enter runs the request and goes to it; Enter only goes", function()
  local screen = open_pane(project())
  -- move onto the 'make-user' row with the keyboard, then Enter
  local function current()
    return screen:exec("local c = require('modules.http_requests').panes()[1]:current(); return c and c.text or ''")
  end
  for _ = 1, 20 do
    if current():find("make-user", 1, true) then
      break
    end
    screen:input("j")
    vim.wait(60)
  end
  lib.matches("make%-user", current(), "could not select the request")
  screen:input("<CR>")
  h.wait(screen, function()
    return where(screen)[1] == "users.http"
  end, "Enter did not go to the request")
  lib.eq(0, screen:exec("return #_G.runs"), "Enter must not run it")
  focus_pane(screen)
  screen:input("<C-CR>")
  h.wait(screen, function()
    return screen:exec("return #_G.runs") == 1
  end, "Ctrl+Enter did not run the request")
  local ran = screen:exec("return _G.runs[1]")
  lib.eq({ "users.http", 7 }, { vim.fn.fnamemodify(ran[1], ":t"), ran[2] }, "it must run with the cursor on the request")
  screen:close()
end)

lib.test("http pane: adding a request appends a block to the file under the cursor", function()
  local dir = project()
  local screen = open_pane(dir)
  click_request(screen, "List users", "users.http") -- the cursor is on a request of users.http
  focus_pane(screen)
  screen:input("a")
  h.wait(screen, function()
    return where(screen)[1] == "users.http" and screen:exec("return vim.api.nvim_get_mode().mode") == "i"
  end, "the new request was not opened for editing")
  local lines = h.read(dir .. "/api/users/users.http")
  lib.eq({ "### New request", "GET https://" }, vim.list_slice(lines, #lines - 1))
  lib.eq("", lines[#lines - 2], "a blank line separates it from the request above")
  lib.eq(#lines, where(screen)[2], "the cursor is on the new URL line")
  screen:close()
end)

lib.test("http pane: a folder asks for a new file name", function()
  local dir = project()
  local screen = open_pane(dir)
  click_on(screen, "auth") -- fold it; the cursor stays on the folder
  h.wait(screen, function()
    return not h.find_on_screen(screen, "login.http")
  end, "the folder did not fold")
  screen:exec("vim.ui.input = function(opts, cb) _G.asked = opts.prompt; cb('fresh') end")
  screen:input("a")
  h.wait(screen, function()
    return vim.uv.fs_stat(dir .. "/auth/fresh.http") ~= nil
  end, "no new file was created")
  lib.eq({ "### New request", "GET https://" }, h.read(dir .. "/auth/fresh.http"))
  lib.matches("auth", screen:exec("return _G.asked"), "the prompt names the folder")
  screen:close()
end)

lib.test("http pane: the clipboard curl button adds it as a request, or says it is not valid", function()
  local dir = project()
  local screen = open_pane(dir)
  click_request(screen, "List users", "users.http")
  focus_pane(screen)

  -- not a curl command: a message, nothing written
  local before = h.read(dir .. "/api/users/users.http")
  screen:exec("_G.clip = 'hello world'")
  click_tool(screen, "curl")
  h.wait(screen, function()
    return screen:exec("return #_G.notes") == 1
  end, "no message for an invalid curl")
  lib.eq("The clipboard does not hold a valid curl command", screen:exec("return _G.notes[1][1]"))
  lib.eq(before, h.read(dir .. "/api/users/users.http"), "an invalid curl must not touch the file")
  screen:exec("_G.clip = ''")
  focus_pane(screen)
  screen:input("P")
  h.wait(screen, function()
    return screen:exec("return #_G.notes") == 2
  end, "no message for an empty clipboard")

  -- a real one
  screen:exec([[_G.clip = "curl -X POST https://api.test/orders -H 'Content-Type: application/json' -d '{\"id\":7}'"]])
  focus_pane(screen)
  screen:input("P")
  h.wait(screen, function()
    return #h.read(dir .. "/api/users/users.http") > #before
  end, "the curl command was not added")
  local lines = h.read(dir .. "/api/users/users.http")
  local added = vim.list_slice(lines, #before + 2)
  lib.eq("### POST https://api.test/orders", added[1])
  lib.matches("^POST https://api.test/orders", added[2])
  lib.ok(vim.tbl_contains(added, "content-type: application/json") or vim.tbl_contains(added, "Content-Type: application/json"), "the header is missing: " .. vim.inspect(added))
  lib.ok(vim.tbl_contains(added, '{"id":7}'), "the body is missing: " .. vim.inspect(added))
  h.wait(screen, function()
    return where(screen)[1] == "users.http" and where(screen)[2] == #before + 3
  end, "the cursor did not go to the new request: " .. vim.inspect(where(screen)))
  lib.eq(2, screen:exec("return #_G.notes"), "a valid curl must not show a message")
  screen:close()
end)

lib.test("http pane: replaces the file explorer, and cmd+b toggles it afterwards", function()
  local screen = open_pane(project())
  local function explorers()
    return screen:exec("return #Snacks.picker.get({ source = 'explorer' })")
  end
  local function panes()
    return screen:exec("return #require('modules.http_requests').panes()")
  end
  screen:exec("Snacks.explorer()")
  h.wait(screen, function()
    return explorers() == 1 and panes() == 0
  end, "opening the explorer must close the http pane")
  screen:input("<Space>h")
  h.wait(screen, function()
    return panes() == 1 and explorers() == 0
  end, "opening the http pane must close the explorer")
  screen:exec("vim.fn.maparg('<D-b>', 'n', false, true).callback()")
  h.wait(screen, function()
    return panes() == 0
  end, "cmd+b must hide the http pane")
  screen:exec("vim.fn.maparg('<D-b>', 'n', false, true).callback()")
  h.wait(screen, function()
    return panes() == 1 and explorers() == 0
  end, "cmd+b must show the http pane again, not the explorer")
  screen:close()
end)

lib.test("http pane: <leader>h focuses an open pane and never closes it", function()
  local screen = open_pane(project())
  screen:input("<Space>h") -- the pane has the focus: it stays open
  vim.wait(300)
  lib.eq(1, screen:exec("return #require('modules.http_requests').panes()"), "<leader>h closed the pane")
  screen:input("<C-w>l")
  screen:input("<Space>h")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_get_current_win() == require('modules.http_requests').panes()[1].list.win.win")
  end, "<leader>h did not put the cursor in the pane")
  screen:close()
end)

lib.test("http pane: Cmd+Shift+H opens the pane over the Explorer and keeps it open", function()
  local screen = h.nvim(project())
  h.wait(screen, function()
    return screen:exec("return package.loaded['kulala'] ~= nil")
  end, "kulala did not load")
  screen:input("<D-S-e>") -- the Explorer first
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'explorer' })") == 1
  end, "the explorer did not open")
  screen:input("<D-S-h>")
  h.wait(screen, function()
    return screen:exec("return #require('modules.http_requests').panes()") == 1
      and screen:exec("return #Snacks.picker.get({ source = 'explorer' })") == 0
      and screen:exec("return vim.o.cmdheight") == 1
  end, "Cmd+Shift+H did not replace the explorer with the pane")
  screen:input("<D-S-h>") -- the pane has the focus: it stays
  vim.wait(300)
  lib.eq(1, screen:exec("return #require('modules.http_requests').panes()"), "Cmd+Shift+H closed the pane")
  screen:close()
end)

lib.test("http pane: a request row is only its name, and the search box does not repeat the title", function()
  local screen = open_pane(project())
  h.wait(screen, function()
    return h.find_on_screen(screen, "List users", 40) ~= nil
  end, "the request did not show")
  lib.ok(h.find_on_screen(screen, "example.com/login", 60) == nil, "the URL of a named request must not show in the pane")
  lib.ok(h.find_on_screen(screen, "example.com/users", 40) ~= nil, "an unnamed request is shown by its URL")
  screen:input("/")
  h.wait(screen, function()
    return screen:exec("return vim.fn.mode()") == "i"
  end, "the search box did not open")
  local titles = 0
  for row = 1, 45 do
    local line = screen:text(row, 1, 40)
    if line:find("HTTP Requests", 1, true) then
      titles = titles + 1
    end
  end
  lib.eq(1, titles, "HTTP Requests must be on the screen once (the winbar), not again in the search box")
  screen:input("log")
  h.wait(screen, function()
    return h.find_on_screen(screen, "Login", 40) ~= nil and h.find_on_screen(screen, "List users", 40) == nil
  end, "searching did not filter the requests")
  screen:close()
end)

-- the text of the row the pane's cursor is on
local function current_row(screen)
  return screen:exec("local c = require('modules.http_requests').panes()[1]:current(); return c and (c.kind .. ':' .. c.text) or ''")
end

local function select_row(screen, kind_text)
  for _ = 1, 30 do
    if current_row(screen) == kind_text then
      return
    end
    screen:input("j")
    vim.wait(50)
  end
  lib.eq(kind_text, current_row(screen), "could not select the row")
end

lib.test("http pane: l opens and h closes folders and files, h on a request goes to its file", function()
  local screen = open_pane(project())
  select_row(screen, "file:users.http")
  screen:input("h") -- open: closes
  h.wait(screen, function()
    return h.find_on_screen(screen, "List users", 40) == nil
  end, "h did not close the file")
  vim.wait(200) -- the refresh puts the cursor back on the file once it is done
  lib.eq("file:users.http", current_row(screen), "the cursor stays on the closed file")
  screen:input("h") -- already closed: goes to the folder it is in
  h.wait(screen, function()
    return current_row(screen) == "dir:users"
  end, "h on a closed file did not go to its folder")
  screen:input("h")
  h.wait(screen, function()
    return h.find_on_screen(screen, "users.http", 40) == nil
  end, "h did not close the folder")
  vim.wait(200)
  screen:input("l")
  h.wait(screen, function()
    return h.find_on_screen(screen, "users.http", 40) ~= nil
  end, "l did not open the folder")
  screen:input("l") -- open: goes to its first row
  h.wait(screen, function()
    return current_row(screen) == "file:users.http"
  end, "l on an open folder did not go to its first row")
  screen:input("l") -- the file is still closed (its state was kept): opens
  h.wait(screen, function()
    return h.find_on_screen(screen, "List users", 40) ~= nil
  end, "l did not open the file")
  vim.wait(200)
  screen:input("l") -- now open: first request
  h.wait(screen, function()
    return current_row(screen):find("^request:") ~= nil
  end, "l on an open file did not go to its first request")
  screen:input("h")
  h.wait(screen, function()
    return current_row(screen) == "file:users.http"
  end, "h on a request did not go to its file")
  lib.eq(0, screen:exec("return #_G.runs"), "h and l must not run anything")
  screen:close()
end)

lib.test("http pane: the terminal cursor is hidden while the pane has the focus and back outside it", function()
  local screen = open_pane(project())
  local function cursor_hidden()
    return screen:exec("return require('modules.pane_kit').hidden()")
  end
  h.wait(screen, cursor_hidden, "the cursor must be hidden in the pane")
  screen:input("/") -- the search box is a place to type
  h.wait(screen, function()
    return not cursor_hidden()
  end, "the cursor must show in the search box")
  screen:input("<Esc><Esc>")
  screen:input("<C-w>l") -- the editor window
  h.wait(screen, function()
    return screen:exec("return #vim.tbl_filter(function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'snacks_picker_list' end, { vim.api.nvim_get_current_win() })") == 0
      and not cursor_hidden()
  end, "the cursor must come back outside the pane")
  screen:close()
end)

lib.test("http pane: an unsaved edit of an open file shows in the pane", function()
  local dir = project()
  local screen = open_pane(dir)
  click_on(screen, "Login") -- opens login.http in the editing window
  h.wait(screen, function()
    return where(screen)[1] == "login.http"
  end, "the file did not open")
  screen:exec([[
    vim.api.nvim_buf_set_lines(0, -1, -1, false, { "", "### Brand new", "GET https://example.com/brand" })
    vim.cmd("doautocmd TextChanged")
  ]])
  h.wait(screen, function()
    return h.find_on_screen(screen, "Brand new", 40) ~= nil -- in the pane, not in the file next to it
  end, "an unsaved request did not show up in the pane")
  screen:close()
end)

lib.test("http pane: .rest files are listed and get the http filetype", function()
  local dir = project()
  h.write(dir .. "/legacy.rest", { "### Old", "GET https://example.com/old" })
  local screen = open_pane(dir)
  lib.ok(h.find_on_screen(screen, "legacy.rest"), "a .rest file is not listed")
  lib.eq("http", screen:exec("return vim.filetype.match({ filename = 'x.rest' })"))
  screen:close()
end)

-- ── edit (the file edits) ───────────────────────────────────────────────────────────────────────
local edit = require("modules.http_requests.edit")

lib.test("http edit: a block goes after one blank line, a new file gets it alone, and saving follows the buffer", function()
  local dir = h.tmpdir()
  -- ends without a blank line: one is added
  h.write(dir .. "/a.http", { "### One", "GET https://x/1" })
  local start, request = edit.append(dir .. "/a.http", { "### Two", "GET https://x/2" })
  lib.eq({ "### One", "GET https://x/1", "", "### Two", "GET https://x/2" }, h.read(dir .. "/a.http"))
  lib.eq({ 4, 5 }, { start, request })
  -- ends with a blank line: no second one
  h.write(dir .. "/b.http", { "### One", "GET https://x/1", "" })
  start, request = edit.append(dir .. "/b.http", { "### Two", "GET https://x/2" })
  lib.eq({ "### One", "GET https://x/1", "", "### Two", "GET https://x/2" }, h.read(dir .. "/b.http"))
  lib.eq({ 4, 5 }, { start, request })
  -- a file that does not exist yet is created with just the block
  start, request = edit.append(dir .. "/sub/new.http", { "### New", "GET https://x/n" })
  lib.eq({ "### New", "GET https://x/n" }, h.read(dir .. "/sub/new.http"))
  lib.eq({ 1, 2 }, { start, request })
  -- a buffer with unsaved edits is changed but not saved
  h.write(dir .. "/c.http", { "### One", "GET https://x/1" })
  local buf = vim.fn.bufadd(dir .. "/c.http")
  vim.fn.bufload(buf)
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "### One edited" })
  edit.append(dir .. "/c.http", { "### Two", "GET https://x/2" })
  lib.eq({ "### One", "GET https://x/1" }, h.read(dir .. "/c.http"), "the file on disk must not change while the buffer has unsaved edits")
  lib.eq("### One edited", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
  lib.eq("### Two", vim.api.nvim_buf_get_lines(buf, -3, -2, false)[1])
end)

-- ── curl (needs Kulala's parser, so it runs in the configured Neovim) ───────────────────────────
lib.test("http curl: commands become requests, anything else is invalid", function()
  local screen = h.nvim(h.tmpdir())
  h.wait(screen, function()
    return screen:exec("return package.loaded['kulala'] ~= nil")
  end, "kulala did not load")
  local function convert(text)
    return screen:exec("local lines, err = require('modules.http_requests.curl').to_lines(...); return { lines = lines, err = err }", { text })
  end
  local get = convert("curl https://api.test/users")
  lib.eq({ "### GET https://api.test/users", "GET https://api.test/users" }, get.lines)
  local post = convert("curl -X POST https://api.test/orders -H 'Accept: application/json' -H 'Content-Type: application/json' -d '{\"id\":7}'")
  lib.eq("### POST https://api.test/orders", post.lines[1])
  lib.eq("POST https://api.test/orders", post.lines[2])
  lib.ok(vim.tbl_contains(post.lines, "accept: application/json") and vim.tbl_contains(post.lines, "content-type: application/json"), vim.inspect(post.lines))
  lib.eq({ "", '{"id":7}' }, vim.list_slice(post.lines, #post.lines - 1))
  local multi = convert("curl -X DELETE \\\n  https://api.test/users/1 \\\n  -H 'X-Token: abc'")
  lib.eq({ "### DELETE https://api.test/users/1", "DELETE https://api.test/users/1", "x-token: abc" }, multi.lines)
  for _, bad in ipairs({ "", "   ", "hello world", "git status", "curl", "curl --verbose" }) do
    local result = convert(bad)
    lib.eq(vim.NIL, result.lines or vim.NIL, "'" .. bad .. "' must not convert")
    lib.eq("The clipboard does not hold a valid curl command", result.err, "'" .. bad .. "'")
  end
  screen:close()
end)

-- ── switching sidebars: the layout must stay whole ─────────────────────────────────────────────
-- (Two Snacks sidebars alive at the same moment made Neovim give half the screen to the command line.)
local function layout(screen)
  return screen:exec([[
    local wins, boxes, lowest = {}, 0, 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative == "" then
        wins[#wins + 1] = vim.api.nvim_win_get_height(win)
        if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "snacks_layout_box" then boxes = boxes + 1 end
      end
    end
    return { cmdheight = vim.o.cmdheight, lines = vim.o.lines, heights = wins, boxes = boxes,
      http = #require("modules.http_requests").panes(), explorers = #Snacks.picker.get({ source = "explorer" }) }
  ]])
end

local function expect_whole(screen, label, sidebar)
  vim.wait(300) -- let the scheduled closes run
  screen:flush()
  local l = layout(screen)
  lib.eq(1, l.cmdheight, label .. ": the command line grew (cmdheight " .. l.cmdheight .. ")")
  for _, height in ipairs(l.heights) do
    lib.ok(height >= l.lines - 3, label .. ": a window is only " .. height .. " rows tall of " .. l.lines .. " " .. vim.inspect(l.heights))
  end
  lib.eq(sidebar == "http" and 1 or 0, l.http, label .. ": http panes")
  lib.eq(sidebar == "explorer" and 1 or 0, l.explorers, label .. ": explorers")
  lib.eq(sidebar and 1 or 0, l.boxes, label .. ": sidebar windows left over: " .. vim.inspect(l))
end

for _, start in ipairs({ "the start screen", "a file" }) do
  lib.test("http pane: switching between the pane and the explorer keeps the layout whole (from " .. start .. ")", function()
    local dir = project()
    local screen = h.nvim(dir)
    h.wait(screen, function()
      return screen:exec("return package.loaded['kulala'] ~= nil")
    end, "kulala did not load")
    if start == "a file" then
      screen:exec("vim.cmd('edit api/health.http')")
    end
    local function wait_for(sidebar)
      h.wait(screen, function()
        local l = layout(screen)
        return (sidebar == "http" and l.http == 1) or (sidebar == "explorer" and l.explorers == 1) or (not sidebar and l.http == 0 and l.explorers == 0)
      end, "the " .. tostring(sidebar) .. " sidebar did not settle")
    end
    local steps = {
      { "explorer", function() screen:exec("Snacks.explorer()") end },
      { "http", function() screen:input("<Space>h") end },
      { "explorer", function() screen:exec("Snacks.explorer()") end },
      { "http", function() screen:exec("vim.fn.maparg('<leader>h', 'n', false, true).callback()") end },
      { "explorer", function() screen:exec("vim.fn.maparg('<leader>e', 'n', false, true).callback()") end },
      { "http", function() screen:exec("require('modules.http_requests').toggle()") end },
      { nil, function() screen:exec("vim.fn.maparg('<D-b>', 'n', false, true).callback()") end }, -- cmd+b hides the pane
      { "http", function() screen:exec("vim.fn.maparg('<D-b>', 'n', false, true).callback()") end },
      { "explorer", function() screen:exec("vim.fn.maparg('<D-S-e>', 'n', false, true).callback()") end },
      { "http", function() screen:input("<Space>h") end },
    }
    expect_whole(screen, "before anything", nil)
    for i, step in ipairs(steps) do
      step[2]()
      wait_for(step[1])
      expect_whole(screen, "step " .. i .. " (" .. tostring(step[1]) .. ")", step[1])
    end
    screen:close()
  end)
end

-- ── in a diff tab (the Git sidebar) ─────────────────────────────────────────────────────────────
local function diff_project()
  local dir = h.repo({
    ["api/users.http"] = { "### List users", "GET https://example.com/users" },
    ["auth/login.http"] = { "### Login", "POST https://example.com/login" },
  })
  h.write(dir .. "/auth/login.http", { "### Login", "POST https://example.com/login", "", "### Extra", "GET https://example.com/extra" })
  return dir
end

local function open_diff_tab(dir)
  local screen = h.nvim(dir)
  h.wait(screen, function()
    return screen:exec("return package.loaded['kulala'] ~= nil")
  end, "kulala did not load")
  screen:exec("vim.cmd('edit auth/login.http'); vim.cmd('CodeDiff scm')")
  h.wait(screen, function()
    return screen:exec("local l = package.loaded['codediff.ui.lifecycle']; return l ~= nil and l.get_panel_view(vim.api.nvim_get_current_tabpage()) ~= nil")
  end, "the Source Control pane never opened")
  return screen
end

lib.test("http pane: from the Git sidebar and back, the layout stays whole", function()
  local screen = open_diff_tab(diff_project())
  local function hidden()
    return screen:exec("local v = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage()); return v ~= nil and v.is_hidden == true")
  end
  screen:input("<Space>h")
  h.wait(screen, function()
    return layout(screen).http == 1 and hidden()
  end, "the pane must replace the Git sidebar")
  vim.wait(300)
  local l = layout(screen)
  lib.eq(1, l.cmdheight, "the command line grew")
  screen:exec("vim.fn.maparg('<D-S-g>', 'n', false, true).callback()")
  h.wait(screen, function()
    return layout(screen).http == 0 and not hidden()
  end, "cmd+shift+g must bring the Git sidebar back and close the pane")
  vim.wait(300)
  lib.eq(1, layout(screen).cmdheight, "the command line grew after going back to Git")
  screen:input("<Space>h")
  h.wait(screen, function()
    return layout(screen).http == 1
  end, "the pane did not open a second time")
  screen:close()
end)

lib.test("http pane: a request chosen in a diff tab opens in another tab and leaves the diff alone", function()
  local dir = diff_project()
  local screen = open_diff_tab(dir)
  local diff_tab = screen:exec("return vim.api.nvim_get_current_tabpage()")
  screen:input("<Space>h")
  h.wait(screen, function()
    return h.find_on_screen(screen, "Extra", 40) ~= nil
  end, "the requests are not on the screen")
  click_on(screen, "Extra")
  h.wait(screen, function()
    return screen:exec("return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t')") == "login.http"
      and screen:exec("return vim.api.nvim_get_current_tabpage()") ~= diff_tab
  end, "the file did not open in another tab")
  -- (the cursor is set right after the file opens: wait for it, do not race it)
  h.wait(screen, function()
    return where(screen)[2] == 5
  end, "the cursor must be on the request (line 5)")
  lib.ok(screen:exec("return require('codediff.ui.lifecycle').get_session(...) ~= nil", { diff_tab }), "the diff session was destroyed")
  screen:close()
end)

-- ── other situations ────────────────────────────────────────────────────────────────────────────
lib.test("http pane: with split windows the pane is full height and files open in the window it was opened from", function()
  local screen = h.nvim(project())
  h.wait(screen, function()
    return screen:exec("return package.loaded['kulala'] ~= nil")
  end, "kulala did not load")
  screen:exec("vim.cmd('edit api/health.http'); vim.cmd('vsplit'); vim.cmd('split'); vim.cmd('edit auth/login.http')")
  screen:input("<Space>h")
  h.wait(screen, function()
    return layout(screen).http == 1
  end, "the pane never opened")
  vim.wait(300)
  local l = layout(screen)
  lib.eq(1, l.cmdheight, "the command line grew")
  lib.eq(1, l.boxes, "one sidebar")
  -- every window of the sidebar column is as tall as the screen; the three editing windows share the rest
  local tall = 0
  for _, height in ipairs(l.heights) do
    if height >= l.lines - 3 then
      tall = tall + 1
    end
  end
  lib.ok(tall >= 2, "the sidebar is not full height: " .. vim.inspect(l.heights))
  click_on(screen, "make-user")
  h.wait(screen, function()
    return where(screen)[1] == "users.http"
  end, "the file did not open")
  screen:close()
end)

lib.test("http pane: closing and reopening keeps what was folded", function()
  local screen = open_pane(project())
  click_on(screen, "auth")
  h.wait(screen, function()
    return not h.find_on_screen(screen, "login.http", 40)
  end, "the folder did not fold")
  screen:input("q")
  h.wait(screen, function()
    return screen:exec("return #require('modules.http_requests').panes()") == 0
  end, "q did not close the pane")
  screen:input("<Space>h")
  h.wait(screen, function()
    return h.find_on_screen(screen, "users.http", 40) ~= nil
  end, "the pane did not reopen")
  lib.ok(not h.find_on_screen(screen, "login.http", 40), "the folded folder opened itself again")
  screen:close()
end)

lib.test("http pane: a project without .http files shows the buttons, and a new request creates the first file", function()
  local dir = h.tmpdir()
  local screen = h.nvim(dir)
  h.wait(screen, function()
    return screen:exec("return package.loaded['kulala'] ~= nil")
  end, "kulala did not load")
  screen:exec("vim.notify = function() end; vim.ui.input = function(opts, cb) cb('first') end")
  screen:input("<Space>h")
  h.wait(screen, function()
    return h.find_on_screen(screen, ICON.new, 40) ~= nil
  end, "the pane did not open in an empty project")
  lib.ok(not h.find_on_screen(screen, ".http", 40), "something is listed in an empty project")
  click_tool(screen, "new")
  h.wait(screen, function()
    return vim.uv.fs_stat(dir .. "/first.http") ~= nil
  end, "the first file was not created")
  lib.eq({ "### New request", "GET https://" }, h.read(dir .. "/first.http"))
  h.wait(screen, function()
    return h.find_on_screen(screen, "first.http", 40) ~= nil
  end, "the new file did not show up in the pane")
  screen:close()
end)

lib.test("http pane: each tab has its own pane", function()
  local screen = open_pane(project())
  screen:exec("vim.cmd('tabnew')")
  screen:input("<Space>h")
  h.wait(screen, function()
    return screen:exec("return #require('modules.http_requests').panes()") == 1
  end, "the second tab got no pane")
  screen:exec("vim.cmd('tabprevious')")
  h.wait(screen, function()
    return screen:exec("return #require('modules.http_requests').panes()") == 1
  end, "the first tab lost its pane")
  screen:close()
end)

lib.test("http pane: folding and unfolding do not flash (the list never jumps)", function()
  local dir = vim.fn.resolve(h.tmpdir())
  for i = 1, 40 do
    local name = string.format("d%02d", i)
    h.write(dir .. "/" .. name .. "/" .. name .. ".http", { "### Req " .. name, "GET https://example.com/" .. name })
  end
  local screen = h.nvim(dir, 120, 30)
  h.wait(screen, function()
    return screen:exec("return package.loaded['kulala'] ~= nil")
  end, "kulala did not load")
  screen:exec("vim.fn.maparg('<leader>h', 'n', false, true).callback()")
  h.wait(screen, function()
    return screen:exec("return #require('modules.http_requests').panes() == 1 and #require('modules.http_requests').panes()[1]:items() > 40")
  end, "the pane has no rows")
  vim.wait(600)
  screen:exec("require('modules.http_requests').panes()[1].list:move(40, true)")
  vim.wait(400)
  local frames = {}
  screen.on_flush = function()
    frames[#frames + 1] = screen:text(5, 1, 54)
  end
  for _, keys in ipairs({ "<CR>", "<CR>", "h", "l" }) do
    frames = {}
    screen:input(keys)
    vim.wait(600)
    local seen, count = {}, 0
    for _, row in ipairs(frames) do
      if not seen[row] then
        seen[row] = true
        count = count + 1
      end
    end
    lib.ok(#frames >= 1, "no frame after " .. keys)
    lib.eq(1, count, "the list jumped while handling " .. keys)
  end
  screen:close()
end)

-- ── hiding folders ──────────────────────────────────────────────────────────────────────────────
local function select_dir(screen, text)
  local row, col = h.find_on_screen(screen, text, 40)
  lib.ok(row, "'" .. text .. "' is not on the screen")
  h.click(screen, row, col + 1)
  -- a click on a folder folds it: unfold again so the rows stay as they were
  h.wait(screen, function()
    return screen:exec("local c = require('modules.http_requests').panes()[1]:current(); return c and c.kind == 'dir'")
  end, "no folder under the cursor")
  screen:input("l")
end

lib.test("http pane: x hides a folder, the eye icon counts the hidden ones and shows them dimmed, x again brings it back", function()
  local dir = project()
  local screen = open_pane(dir)
  screen:exec("require('modules.http_requests.hidden').set_file(...)", { dir .. "/hidden.json" })
  lib.ok(h.find_on_screen(screen, "login.http", 40), "the file of the folder is there")
  select_dir(screen, "auth")
  screen:input("x")
  h.wait(screen, function()
    return h.find_on_screen(screen, "login.http", 40) == nil and h.find_on_screen(screen, "auth", 40) == nil
  end, "x did not hide the folder")
  lib.ok(h.find_on_screen(screen, ICON.hidden .. " 1", 40), "the eye must show 1 hidden folder")
  -- the eye shows them, dimmed, with all their content
  local row, col = h.find_on_screen(screen, ICON.hidden, 40)
  h.click(screen, row, col)
  h.wait(screen, function()
    return h.find_on_screen(screen, "auth", 40) ~= nil and h.find_on_screen(screen, ICON.hidden_on .. " 1", 40) ~= nil
  end, "the eye did not show the hidden folder")
  lib.ok(h.find_on_screen(screen, "login.http", 40) and h.find_on_screen(screen, "Login", 40), "a shown hidden folder keeps all its content")
  -- x on it brings it back
  select_dir(screen, "auth")
  screen:input("x")
  h.wait(screen, function()
    return h.find_on_screen(screen, ICON.hidden_on .. " 0", 40) ~= nil
  end, "the count must go back to 0")
  lib.ok(h.find_on_screen(screen, "login.http", 40), "the folder has its content again")
  screen:close()
end)

lib.test("http pane: p pins a request under Pinned (a reference, it also stays in its folder), p there unpins it, pins are remembered", function()
  local dir = project()
  local memory = dir .. "/pinned.json"
  local screen = open_pane(dir)
  screen:exec("require('modules.http_requests.pinned').set_file(...)", { memory })
  lib.ok(h.find_on_screen(screen, "Pinned", 40) == nil, "no Pinned section without pins")
  local function on_request(text)
    local row, col = h.find_on_screen(screen, text, 40)
    lib.ok(row, text .. " is not on the screen")
    h.click(screen, row, col + 1)
    h.wait(screen, function() return where(screen)[1] ~= nil end, "")
    focus_pane(screen)
    h.wait(screen, function()
      return screen:exec("local c = require('modules.http_requests').panes()[1]:current(); return c and c.kind == 'request' and c.req.name == ...", { text })
    end, "the cursor is not on " .. text)
  end
  on_request("make-user")
  screen:input("p")
  h.wait(screen, function()
    return h.find_on_screen(screen, "Pinned", 40) ~= nil
  end, "p did not create the Pinned section")
  local pin_row = h.find_on_screen(screen, "Pinned", 40)
  local req_row = h.find_on_screen(screen, "make-user", 40)
  lib.ok(req_row == pin_row + 1, "the pinned request must be right under Pinned")
  lib.ok(select(1, h.find_on_screen(screen, "users.http  ", 40)) ~= nil or h.find_on_screen(screen, "users.http", 40), "its file is shown next to it")
  -- a reference: the request stays in its file too, so it is listed twice
  local count = screen:exec("local n = 0; for _, i in ipairs(require('modules.http_requests').panes()[1]:items()) do if i.kind == 'request' and i.req.name == 'make-user' then n = n + 1 end end; return n")
  lib.eq(2, count)
  -- the pin is remembered
  lib.eq(1, screen:exec("return #require('modules.http_requests.pinned').list(vim.uv.cwd())"))
  -- p on the pinned row unpins
  screen:exec("local p = require('modules.http_requests').panes()[1]; for i, it in ipairs(p:items()) do if it.in_pins then p.list:move(i, true) end end")
  screen:input("p")
  h.wait(screen, function()
    return h.find_on_screen(screen, "Pinned", 40) == nil
  end, "p on the pinned request did not unpin it")
  lib.ok(h.find_on_screen(screen, "make-user", 40), "the request is back in its file")
  screen:close()
end)

lib.test("http pane: hidden folders are remembered after closing Neovim", function()
  local dir = project()
  local memory = dir .. "/hidden.json"
  local first = open_pane(dir)
  first:exec("require('modules.http_requests.hidden').set_file(...)", { memory })
  select_dir(first, "auth")
  first:input("x")
  h.wait(first, function()
    return h.find_on_screen(first, "login.http", 40) == nil
  end, "the folder was not hidden")
  first:close()
  local second = open_pane(dir) -- a new Neovim, same project
  second:exec("require('modules.http_requests.hidden').set_file(...)", { memory })
  second:exec("require('modules.http_requests').panes()[1]:find()")
  h.wait(second, function()
    return h.find_on_screen(second, ICON.hidden .. " 1", 40) ~= nil
  end, "the second session does not know the hidden folder")
  lib.ok(h.find_on_screen(second, "login.http", 40) == nil and h.find_on_screen(second, "auth", 40) == nil, "it must stay hidden")
  lib.ok(h.find_on_screen(second, "health.http", 40), "the other folders are there")
  second:close()
end)

lib.test("http pane: the toolbar is three icons, no text", function()
  local screen = open_pane(project())
  lib.ok(h.find_on_screen(screen, ICON.new, 40) and h.find_on_screen(screen, ICON.curl, 40) and h.find_on_screen(screen, ICON.hidden .. " 0", 40), "the three icons")
  lib.ok(not h.find_on_screen(screen, "New request", 40) and not h.find_on_screen(screen, "clipboard", 40), "no button text")
  screen:close()
end)

lib.test("http pane: ? shows the keys in a small window, Esc closes it", function()
  local screen = open_pane(project())
  screen:input("?")
  h.wait(screen, function()
    return h.find_on_screen(screen, "HTTP pane keys") ~= nil and h.find_on_screen(screen, "hide / unhide folder") ~= nil
  end, "? did not show the keys")
  screen:input("<Esc>")
  h.wait(screen, function()
    return h.find_on_screen(screen, "HTTP pane keys") == nil
  end, "Esc did not close the help")
  lib.eq(1, screen:exec("return #require('modules.http_requests').panes()"), "the pane itself stays open")
  screen:close()
end)
