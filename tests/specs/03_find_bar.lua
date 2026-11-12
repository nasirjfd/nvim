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
  return screen:exec([[
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)):find(..., 1, true) then
        return { vim.api.nvim_win_get_cursor(win)[1], vim.api.nvim_win_call(win, function() return vim.fn.line("w0") end) }
      end
    end
  ]], { name })
end

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
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_get_mode().mode") == "s"
  end, "the previous search is not selected (mode " .. tostring(screen:exec("return vim.api.nvim_get_mode().mode")) .. ")")
  screen:input("5")
  h.wait(screen, function()
    return bar_text(screen) == "5"
  end, "typing did not replace the selected search: " .. tostring(bar_text(screen)))
  screen:close()
end)

lib.test("find bar: typing shows a match on the screen instead of wrapping to the top of the file", function()
  local dir = h.tmpdir()
  local lines = {}
  for i = 1, 200 do
    lines[i] = "line " .. i
  end
  lines[3] = "needle at the top"
  lines[95] = "needle on the screen"
  h.write(dir .. "/big.txt", lines)
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit big.txt'); vim.cmd('normal! 90Gzt'); vim.api.nvim_win_set_cursor(0, { 100, 0 })")
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
end)

lib.test("find bar: with no match on the screen it still goes to the first one from the cursor", function()
  local dir = h.tmpdir()
  local lines = {}
  for i = 1, 200 do
    lines[i] = "line " .. i
  end
  lines[3] = "needle at the top"
  h.write(dir .. "/big.txt", lines)
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit big.txt'); vim.cmd('normal! 90Gzt'); vim.api.nvim_win_set_cursor(0, { 100, 0 })")
  screen:input("/")
  h.wait(screen, function()
    return bar_text(screen) ~= false
  end, "the find bar never opened")
  screen:input("needle")
  h.wait(screen, function()
    return file_view(screen, "big.txt")[1] == 3
  end, "did not wrap to the only match")
  screen:close()
end)
