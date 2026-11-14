local lib = require("lib")
local h = require("support")

local function editor(lines)
  local screen = h.nvim(h.tmpdir())
  screen:exec(
    [[
    vim.cmd('enew')
    vim.opt.clipboard = ''
    vim.api.nvim_buf_set_lines(0, 0, -1, false, ...)
    vim.fn.setreg('z', 'keep z')
    vim.fn.setreg('0', 'keep zero')
    vim.fn.setreg('a', 'keep unnamed')
    vim.fn.setreg('"', { points_to = 'a' })
  ]],
    { lines }
  )
  return screen
end

local cases = {
  {
    name = "partial text",
    lines = { "abcdef" },
    keys = "gg0v2l",
    expected = { "abcabcdef" },
    selected = { "abc" },
  },
  {
    name = "backward selection",
    lines = { "abcdef" },
    keys = "gg03lv2h",
    expected = { "abcdbcdef" },
    selected = { "bcd" },
  },
  {
    name = "Unicode",
    lines = { "aسلامz" },
    keys = "gg0lv",
    cursor = { 1, 7 },
    expected = { "aسلامسلامz" },
    selected = { "سلام" },
  },
  {
    name = "multiline text",
    lines = { "abcDEF", "GHIjkl" },
    keys = "gg03lvjh",
    expected = { "abcDEF", "GHIDEF", "GHIjkl" },
    selected = { "DEF", "GHI" },
  },
  {
    name = "whole lines",
    lines = { "one", "two", "three" },
    keys = "ggVj",
    expected = { "one", "two", "one", "two", "three" },
    selected = { "one", "two" },
  },
  {
    name = "rectangular selection",
    lines = { "abcd", "efgh" },
    keys = "gg0l\22jl",
    expected = { "abcbcd", "efgfgh" },
    selected = { "bc", "fg" },
  },
}

for _, case in ipairs(cases) do
  lib.test("cmd+d duplicates exactly " .. case.name .. " and preserves registers", function()
    local screen = editor(case.lines)
    screen:exec("vim.cmd('normal! ' .. ...)", { case.keys })
    if case.cursor then
      screen:exec("vim.api.nvim_win_set_cursor(0, ...)", { case.cursor })
    end
    screen:input("<D-d>")
    h.wait(screen, function()
      return vim.deep_equal(
        case.expected,
        screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
      )
    end, function()
      return "Cmd+D did not duplicate the exact selection: "
        .. vim.inspect(screen:exec([[
        return { lines=vim.api.nvim_buf_get_lines(0,0,-1,false),
          selected=vim.fn.getregion(vim.fn.getpos('v'),vim.fn.getpos('.'),{type=vim.fn.mode()}),
          selection=vim.o.selection, error=vim.v.errmsg }
      ]]))
    end)
    lib.eq(
      case.selected,
      screen:exec([[
      return vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = vim.fn.mode() })
    ]]),
      "new copy was not selected"
    )
    lib.eq(
      { "keep z", "keep zero", "keep unnamed" },
      screen:exec([[
      return {vim.fn.getreg('z'), vim.fn.getreg('0'), vim.fn.getreg('"')}
    ]]),
      "duplication changed registers"
    )
    screen:close()
  end)
end

lib.test("cmd+d repeats duplication and one undo removes only the latest copy", function()
  local screen = editor({ "abcdef" })
  screen:exec("vim.cmd('normal! gg0v2l')")
  screen:input("<D-d><D-d>")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_get_current_line()") == "abcabcabcdef"
  end, "repeated Cmd+D duplicated the wrong text")
  screen:input("<Esc>")
  h.wait(screen, function()
    return screen:exec("return vim.fn.mode()") == "n"
  end, "Escape did not leave the selection")
  screen:input("u")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_get_current_line()") == "abcabcdef"
  end, function()
    return "undo did not remove only the latest copy: "
      .. screen:exec("return vim.api.nvim_get_current_line()")
  end)
  screen:close()
end)

lib.test("cmd+d with no selection duplicates the line in normal and insert mode", function()
  local screen = editor({ "abc", "def" })
  screen:exec("vim.api.nvim_win_set_cursor(0, { 1, 1 })")
  screen:input("<D-d>")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_buf_line_count(0)") == 3
  end, "normal-mode line was not duplicated")
  screen:input("i<D-d>")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_buf_line_count(0)") == 4
  end, "insert-mode line was not duplicated")
  lib.eq(
    { "abc", "abc", "abc", "def" },
    screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  )
  lib.eq("i", screen:exec("return vim.fn.mode()"), "duplication left insert mode")
  screen:close()
end)

lib.test("cmd+d does not overwrite the clipboard with unnamedplus enabled", function()
  local screen = editor({ "abcdef" })
  screen:exec([[
    _G.duplicate_clipboard = { 'keep clipboard' }
    _G.duplicate_clipboard_writes = 0
    local function copy(lines)
      _G.duplicate_clipboard = lines
      _G.duplicate_clipboard_writes = _G.duplicate_clipboard_writes + 1
    end
    local function paste() return { _G.duplicate_clipboard, 'v' } end
    vim.g.clipboard = { name = 'test', copy = { ['+'] = copy, ['*'] = copy },
      paste = { ['+'] = paste, ['*'] = paste }, cache_enabled = 0 }
    vim.g.loaded_clipboard_provider = nil
    vim.cmd('runtime autoload/provider/clipboard.vim')
    vim.opt.clipboard = 'unnamedplus'
    vim.fn.setreg('"', { points_to = '+' })
    vim.cmd('normal! gg0v2l')
  ]])
  screen:input("<D-d>")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_get_current_line()") == "abcabcdef"
  end, "selection was not duplicated")
  lib.eq("keep clipboard", screen:exec("return vim.fn.getreg('+')"))
  lib.eq(
    0,
    screen:exec("return _G.duplicate_clipboard_writes"),
    "duplication wrote to the clipboard"
  )
  screen:close()
end)
