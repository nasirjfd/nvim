local lib = require("lib")
local h = require("support")

-- Right-to-left text (lua/core/rtl.lua, GNU FriBidi): lines with RTL letters are drawn in visual order
-- over the real text, except the cursor line; nothing else about editing changes.

local LINES = {
  "local english = 1",
  "سلام world",
  "-- می‌خواهم test",
  "plain english line",
}

local function open(screen, dir)
  h.write(dir .. "/a.txt", LINES)
  screen:exec(("vim.cmd.edit(%q)"):format(dir .. "/a.txt"))
end

lib.test("rtl: FriBidi orders and joins the letters, English lines are left alone", function()
  local screen = h.nvim(h.tmpdir())
  local r = screen:exec([[
    local rtl = require("core.rtl")
    return {
      rtl.available(),
      rtl.render("سلام world", 8),
      rtl.render("-- می‌خواهم test", 8),
      rtl.render("x = 'لا ۱۲۳ abc'", 8),
      rtl.render("plain english", 8) == nil,
    }
  ]])
  lib.ok(r[1], "GNU FriBidi is not installed: brew install fribidi")
  lib.eq({ col = 0, text = "ﻡﻼﺳ" }, r[2])
  -- a ZWNJ inside a word: joined forms stop at it, the rest of the line is not touched
  lib.eq({ col = 3, text = "ﻢﻫﺍﻮﺧﯽﻣ" }, r[3])
  -- numbers keep their order inside right-to-left text
  lib.eq({ col = 5, text = "۱۲۳ ﻻ" }, r[4])
  lib.ok(r[5], "an English line got an overlay")
  screen:close()
end)

lib.test("rtl: drawn in visual order except on the cursor line", function()
  local dir = h.tmpdir()
  local screen = h.nvim(dir)
  open(screen, dir)
  h.wait(screen, function()
    return h.find_on_screen(screen, "ﻡﻼﺳ world")
      and h.find_on_screen(screen, "ﻢﻫﺍﻮﺧﯽﻣ test")
  end, "the RTL lines are not drawn in visual order")
  -- on the cursor line the real text is shown (it is edited there), and back when the cursor leaves
  screen:input("j")
  h.wait(screen, function()
    return not h.find_on_screen(screen, "ﻡﻼﺳ world")
      and h.find_on_screen(screen, "ﻢﻫﺍﻮﺧﯽﻣ test")
  end, "the cursor line is not drawn raw")
  screen:input("jj")
  h.wait(screen, function()
    return h.find_on_screen(screen, "ﻡﻼﺳ world")
      and h.find_on_screen(screen, "ﻢﻫﺍﻮﺧﯽﻣ test")
  end, "the line is not drawn in visual order again after the cursor left")
  -- :Rtl turns it off and on
  screen:command("Rtl")
  h.wait(screen, function()
    return not h.find_on_screen(screen, "ﻡﻼﺳ world")
  end, ":Rtl did not turn it off")
  screen:command("Rtl")
  h.wait(screen, function()
    return h.find_on_screen(screen, "ﻡﻼﺳ world")
  end, ":Rtl did not turn it back on")
  screen:close()
end)

lib.test("rtl: typing, search and pickers behave exactly as without it", function()
  local dir = h.tmpdir()
  local screen = h.nvim(dir)
  local before =
    screen:exec("return { vim.o.guicursor, vim.wo.conceallevel, vim.wo.concealcursor }")
  open(screen, dir)
  -- typing English and Persian on a line: the text is exactly what was typed, the cursor after it
  screen:input("Gofoo سلام bar<Esc>")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_get_current_line()") == "foo سلام bar"
  end, function()
    return "typed text differs: " .. screen:exec("return vim.api.nvim_get_current_line()")
  end)
  lib.eq({ 5, 15 }, screen:exec("return vim.api.nvim_win_get_cursor(0)"))
  -- search finds English and Persian and puts the cursor on the match
  -- (/ is the find bar: it keeps the focus and moves the file's cursor to the match)
  local file_cursor = [[
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)):match("a%.txt$") then
        return vim.api.nvim_win_get_cursor(w)
      end
    end
  ]]
  screen:input("gg/world")
  h.wait(screen, function()
    return vim.deep_equal(screen:exec(file_cursor), { 2, 9 })
  end, function()
    return "search for an English word on an RTL line went to "
      .. vim.inspect(screen:exec(file_cursor))
  end)
  lib.eq("world", screen:exec("return vim.api.nvim_get_current_line()"))
  screen:input("<Esc>")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_buf_get_name(0)"):match("a%.txt$") ~= nil
  end, "the find bar did not close")
  -- Esc leaves the cursor one column before the match, as it does on an English-only line
  lib.eq({ 2, 8 }, screen:exec("return vim.api.nvim_win_get_cursor(0)"))
  screen:command("normal! gg")
  screen:exec([[vim.fn.search("می")]])
  lib.eq({ 3, 3 }, screen:exec("return vim.api.nvim_win_get_cursor(0)"))
  -- options are never changed
  lib.eq(
    before,
    screen:exec("return { vim.o.guicursor, vim.wo.conceallevel, vim.wo.concealcursor }")
  )
  -- a picker input: what is typed stays, the cursor stays at its end
  screen:exec("Snacks.picker.files()")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'snacks_picker_input'")
  end, "the file picker did not open")
  screen:input("abc")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_get_current_line()") == "abc"
  end, "the picker input lost what was typed")
  vim.wait(200) -- nothing else happens: no redraw moves the cursor back
  lib.eq("abc", screen:exec("return vim.api.nvim_get_current_line()"))
  lib.eq(3, screen:exec("return vim.api.nvim_win_get_cursor(0)[2]"))
  local messages = screen:exec("return vim.fn.execute('messages')")
  lib.ok(not messages:find("rtl") and not messages:find("Error"), "errors were shown: " .. messages)
  screen:close()
end)

lib.test("rtl: Persian values in Kulala's response window read right to left", function()
  local screen = h.nvim(h.tmpdir())
  -- Kulala's response buffer (kulala://ui) is a nofile buffer: it opts in when it is shown
  screen:exec([[
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "kulala://ui")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "{", '  "message_fa": "می‌خواهم",', "}" })
    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  ]])
  h.wait(screen, function()
    return h.find_on_screen(screen, "ﻢﻫﺍﻮﺧﯽﻣ") ~= nil
  end, "the Persian value is not drawn right to left in Kulala's response")
  screen:close()
end)
