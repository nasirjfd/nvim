-- `/` opens the find bar with the previous search selected: typing replaces it, like a text field.
local lib = require("lib")
local h = require("support")

local function bar_text(screen)
  return screen:exec([[
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "findbar" then
        return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      end
    end
    return false
  ]])
end

-- cursor line and top line of the window that shows `name` (the bar has the focus while typing)
local function file_view(screen, name)
  return screen:exec(
    [[
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)):find(..., 1, true) then
        return { vim.api.nvim_win_get_cursor(win)[1], vim.api.nvim_win_call(win, function() return vim.fn.line("w0") end) }
      end
    end
  ]],
    { name }
  )
end

lib.test("find bar: one Escape closes a reopened search while its old text is selected", function()
  local screen = h.nvim(h.tmpdir())
  screen:input("/proof")
  h.wait(screen, function()
    return bar_text(screen) == "proof"
  end, "first search did not open")
  screen:input("<Esc>")
  h.wait(screen, function()
    return bar_text(screen) == false
  end, "first search did not close")
  screen:input("/")
  h.wait(screen, function()
    return screen:exec("return vim.fn.mode()") == "s"
  end, "old search was not selected")
  screen:input("<Esc>")
  h.wait(screen, function()
    return bar_text(screen) == false and screen:exec("return vim.fn.mode()") == "n"
  end, "Escape only left Select mode instead of closing the bar")
  screen:close()
end)

lib.test("find bar: slash and Cmd+F always type p literally after reopening", function()
  local screen = h.nvim(h.tmpdir())
  screen:exec([[
    vim.opt.clipboard = ''
    vim.fn.setreg('a', 'CLIPBOARD_CODE_MUST_NOT_BE_PASTED')
    vim.fn.setreg('"', { points_to = 'a' })
  ]])
  for i = 1, 12 do
    screen:input(i % 2 == 0 and "<D-f>" or "/")
    h.wait(screen, function()
      return bar_text(screen) ~= false and screen:exec("return vim.fn.mode():match('^[is]') ~= nil")
    end, "find bar did not enter text-entry mode")
    screen:input("proof")
    h.wait(screen, function()
      return bar_text(screen) == "proof" and screen:exec("return vim.fn.mode()") == "i"
    end, "typing proof ran a Normal-mode command: " .. tostring(bar_text(screen)))
    screen:input("<CR><Down><Up>")
    vim.wait(30)
    lib.eq("i", screen:exec("return vim.fn.mode()"), "navigation left text-entry mode")
    screen:input("<Esc>")
    h.wait(screen, function()
      return bar_text(screen) == false
    end, "Escape did not close the search")
  end
  screen:close()
end)

lib.test("find bar: focused input recovers from leaving Insert mode", function()
  local screen = h.nvim(h.tmpdir())
  screen:input("/proof")
  h.wait(screen, function()
    return bar_text(screen) == "proof" and screen:exec("return vim.fn.mode()") == "i"
  end, "search field did not enter Insert mode")
  screen:exec("vim.cmd('stopinsert')")
  h.wait(screen, function()
    return screen:exec("return vim.fn.mode()") == "i"
  end, "search field stayed in Normal mode")
  screen:input("<Esc>")
  h.wait(screen, function()
    return bar_text(screen) == false and screen:exec("return vim.fn.mode()") == "n"
  end, "mode guard prevented Escape from closing the field")
  screen:close()
end)

lib.test("find bar: the previous search is selected on reopening, typing replaces it", function()
  local dir = h.tmpdir()
  h.write(dir .. "/a.txt", { "CHANGED here", "other 5", "CHANGED again" })
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit a.txt')")
  screen:input("/")
  h.wait(screen, function()
    return bar_text(screen) ~= false
  end, "the find bar never opened")
  screen:input("CHANGED")
  h.wait(screen, function()
    return bar_text(screen) == "CHANGED"
  end, "typing did not reach the find bar")
  screen:input("<Esc>")
  h.wait(screen, function()
    return bar_text(screen) == false
  end, "Esc did not close the find bar")
  screen:input("/")
  h.wait(screen, function()
    return bar_text(screen) == "CHANGED"
  end, "the previous search is not in the bar")
  -- selected: Neovim is in Select mode over the whole text
  h.wait(
    screen,
    function()
      return screen:exec("return vim.api.nvim_get_mode().mode") == "s"
    end,
    "the previous search is not selected (mode "
      .. tostring(screen:exec("return vim.api.nvim_get_mode().mode"))
      .. ")"
  )
  screen:input("5")
  h.wait(screen, function()
    return bar_text(screen) == "5"
  end, "typing did not replace the selected search: " .. tostring(bar_text(screen)))
  screen:close()
end)

lib.test(
  "find bar: typing shows a match on the screen instead of wrapping to the top of the file",
  function()
    local dir = h.tmpdir()
    local lines = {}
    for i = 1, 200 do
      lines[i] = "line " .. i
    end
    lines[3] = "needle at the top"
    lines[95] = "needle on the screen"
    h.write(dir .. "/big.txt", lines)
    local screen = h.nvim(dir)
    screen:exec(
      "vim.cmd('edit big.txt'); vim.cmd('normal! 90Gzt'); vim.api.nvim_win_set_cursor(0, { 100, 0 })"
    )
    screen:input("/")
    h.wait(screen, function()
      return bar_text(screen) ~= false
    end, "the find bar never opened")
    screen:input("needle")
    h.wait(screen, function()
      return bar_text(screen) == "needle"
    end, "typing did not reach the find bar")
    screen:exec("vim.wait(200)")
    local view = file_view(screen, "big.txt")
    lib.eq(95, view[1], "went to the match above the cursor on the screen")
    lib.eq(90, view[2], "the view did not move")
    screen:close()
  end
)

lib.test(
  "find bar: with no match on the screen it still goes to the first one from the cursor",
  function()
    local dir = h.tmpdir()
    local lines = {}
    for i = 1, 200 do
      lines[i] = "line " .. i
    end
    lines[3] = "needle at the top"
    h.write(dir .. "/big.txt", lines)
    local screen = h.nvim(dir)
    screen:exec(
      "vim.cmd('edit big.txt'); vim.cmd('normal! 90Gzt'); vim.api.nvim_win_set_cursor(0, { 100, 0 })"
    )
    screen:input("/")
    h.wait(screen, function()
      return bar_text(screen) ~= false
    end, "the find bar never opened")
    screen:input("needle")
    h.wait(screen, function()
      return file_view(screen, "big.txt")[1] == 3
    end, "did not wrap to the only match")
    screen:close()
  end
)

local function big_file(screen_dir)
  local lines = {}
  for i = 1, 200 do
    lines[i] = "line " .. i
  end
  lines[3] = "needle at the top"
  lines[150] = "needle far below"
  lines[160] = "other thing"
  h.write(screen_dir .. "/big.txt", lines)
end

lib.test(
  "find bar: reopening on the previous search stays where it is and highlights; Enter or a change goes to it",
  function()
    local dir = h.tmpdir()
    big_file(dir)
    local screen = h.nvim(dir)
    screen:exec(
      "vim.cmd('edit big.txt'); vim.cmd('normal! 90Gzt'); vim.api.nvim_win_set_cursor(0, { 100, 0 })"
    )
    -- a first search, then close the bar
    screen:input("/")
    h.wait(screen, function()
      return bar_text(screen) ~= false
    end, "the find bar never opened")
    screen:input("needle")
    h.wait(screen, function()
      return bar_text(screen) == "needle"
    end, "typing did not reach the find bar")
    screen:input("<Esc>")
    h.wait(screen, function()
      return bar_text(screen) == false
    end, "Esc did not close the bar")
    screen:exec(
      "vim.api.nvim_win_set_cursor(0, { 100, 0 }); vim.cmd('normal! 90Gzt'); vim.api.nvim_win_set_cursor(0, { 100, 0 })"
    )
    -- reopen: nothing moves, the matches are highlighted
    screen:input("/")
    h.wait(screen, function()
      return bar_text(screen) == "needle"
    end, "the previous search is not in the bar")
    screen:exec("vim.wait(300)")
    local view = file_view(screen, "big.txt")
    lib.eq({ 100, 90 }, view, "opening the bar moved the cursor or the view")
    lib.eq(1, screen:exec("return vim.v.hlsearch"), "the matches are not highlighted")
    -- Enter: now it goes to the first match from the cursor
    screen:input("<CR>")
    h.wait(screen, function()
      return file_view(screen, "big.txt")[1] == 150
    end, "Enter did not go to the match")
    -- a changed text also goes
    screen:exec("require('core.find-bar').close()")
    h.wait(screen, function()
      return bar_text(screen) == false
    end, "the bar did not close")
    screen:exec("vim.api.nvim_win_set_cursor(0, { 100, 0 })")
    screen:input("/")
    h.wait(screen, function()
      return bar_text(screen) == "needle"
    end, "no bar")
    screen:exec("vim.wait(300)")
    lib.eq(100, file_view(screen, "big.txt")[1], "reopening moved the cursor again")
    screen:input("other")
    h.wait(screen, function()
      return file_view(screen, "big.txt")[1] == 160
    end, "typing a new text did not go to its match")
    screen:close()
  end
)
