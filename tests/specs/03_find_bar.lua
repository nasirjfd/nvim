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
