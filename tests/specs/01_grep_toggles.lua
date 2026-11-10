-- <leader>/ : case-insensitive, plain-text by default, with Aa / ab / .* buttons that really react to the
-- mouse (the hover colour lands on the button under the pointer, on the real rendered cells).
local lib = require("lib")
local h = require("support")
local Screen = require("screen") -- luacheck: ignore

local function files()
  local dir = h.tmpdir()
  h.write(dir .. "/g.txt", { "Hello World", "hello there", "HELLO.x", "helloworld" })
  return dir
end

local function open_grep(dir, query)
  local screen = h.nvim(dir)
  screen:exec("Snacks.picker.grep({ cwd = ... })", { dir })
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'grep' }) == 1")
  end, "the grep picker never opened")
  screen:input(query)
  return screen
end

local function set_query(screen, text)
  screen:exec("local p = Snacks.picker.get({ source = 'grep' })[1]; p.input:set(..., ...); p:find()", { text })
end

local function matches(screen)
  return screen:exec("local p = Snacks.picker.get({ source = 'grep' })[1]; return p and p:count() or -1")
end

local function expect_matches(screen, n, message)
  h.wait(screen, function()
    return matches(screen) == n
  end, message .. " (expected " .. n .. " matches, have " .. tostring(matches(screen)) .. ")")
end

-- the row and the columns of the three buttons
local function buttons(screen)
  local row = h.find_on_screen(screen, "Aa")
  lib.ok(row, "the buttons are not on the screen")
  local out = {}
  for _, label in ipairs({ "Aa", "ab", ".*" }) do
    out[#out + 1] = { label = label, col = h.find_on_row(screen, row, label) }
  end
  return row, out
end

lib.test("grep: case-insensitive and plain text by default", function()
  local screen = open_grep(files(), "hello")
  expect_matches(screen, 4, "hello must find Hello, hello and HELLO")
  set_query(screen, "hel+o")
  expect_matches(screen, 0, "hel+o is plain text, not a regex")
  screen:close()
end)

lib.test("grep: the buttons toggle case, whole word and regex when clicked", function()
  local screen = open_grep(files(), "hello")
  expect_matches(screen, 4, "default")
  local row, b = buttons(screen)
  h.click(screen, row, b[1].col + 1) -- Aa: match case
  expect_matches(screen, 2, "match case must keep hello and helloworld")
  h.click(screen, row, b[2].col + 1) -- ab: whole word
  expect_matches(screen, 1, "match case + whole word must keep only 'hello there'")
  h.click(screen, row, b[1].col + 1) -- Aa off again
  expect_matches(screen, 3, "whole word, any case: Hello, hello and HELLO")
  set_query(screen, "hel+o")
  expect_matches(screen, 0, "no regex yet")
  h.click(screen, row, b[3].col + 1) -- .*: regex on
  expect_matches(screen, 3, "regex hel+o as a whole word, any case")
  screen:close()
end)

lib.test("grep: A-c / A-w / A-r toggle the same options from the keyboard", function()
  local screen = open_grep(files(), "hello")
  expect_matches(screen, 4, "default")
  screen:input("<A-c>")
  expect_matches(screen, 2, "A-c")
  screen:input("<A-w>")
  expect_matches(screen, 1, "A-w")
  screen:close()
end)

for _, state in ipairs({ "no results yet", "with results" }) do
  lib.test("grep: the hover colour is on the button under the pointer (" .. state .. ")", function()
    local screen = open_grep(files(), state == "with results" and "hello" or "")
    if state == "with results" then
      expect_matches(screen, 4, "results")
    end
    local row, b = buttons(screen)
    local hover_bg = screen:exec("return vim.api.nvim_get_hl(0, { name = 'GrepToggle_hover' }).bg")
    local off_bg = screen:exec("return vim.api.nvim_get_hl(0, { name = 'GrepToggle_off' }).bg")
    for i, target in ipairs(b) do
      h.hover(screen, row, target.col + 1)
      h.wait(screen, function()
        return screen:highlight(row, target.col + 1).background == hover_bg
      end, "button " .. target.label .. " never got the hover colour")
      for j, other in ipairs(b) do
        if j ~= i then
          lib.eq(off_bg, screen:highlight(row, other.col + 1).background, target.label .. " hovered, but " .. other.label .. " is lit")
        end
      end
    end
    -- off the buttons: no hover colour anywhere
    h.hover(screen, row + 3, b[1].col + 1)
    h.wait(screen, function()
      return screen:highlight(row, b[1].col + 1).background == off_bg
    end, "the hover colour stayed after the pointer left")
    screen:close()
  end)
end

lib.test("grep: the title carries no stray 'R' flag", function()
  local screen = open_grep(files(), "hello")
  expect_matches(screen, 4, "results")
  local row = h.find_on_screen(screen, "Grep")
  lib.ok(row, "no Grep title")
  lib.ok(not h.row_text(screen, row):find("Grep.-R"), "the title shows a regex flag: " .. h.row_text(screen, row))
  screen:close()
end)
