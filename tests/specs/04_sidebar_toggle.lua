-- Cmd+B toggles whichever sidebar was opened last: the Explorer after Cmd+Shift+E, Git after Cmd+Shift+G.
local lib = require("lib")
local h = require("support")

local function explorer_open(screen)
  return screen:exec("return #Snacks.picker.get({ source = 'explorer' }) > 0 and Snacks.picker.get({ source = 'explorer' })[1].closed ~= true")
end

local function press(screen, key)
  screen:exec("vim.fn.maparg(..., 'n', false, true).callback()", { key })
end

lib.test("cmd+b keeps toggling the explorer after cmd+shift+e in a git tab, and git after cmd+shift+g", function()
  local dir = h.repo({ ["a.txt"] = { "one", "two" } })
  h.write(dir .. "/a.txt", { "one", "CHANGED" })
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit a.txt'); vim.cmd('CodeDiff scm')")
  h.wait(screen, function()
    return screen:exec("local l = package.loaded['codediff.ui.lifecycle']; return l ~= nil and l.get_panel_view(vim.api.nvim_get_current_tabpage()) ~= nil")
  end, "the Source Control pane never opened")

  press(screen, "<D-S-e>")
  h.wait(screen, function()
    return explorer_open(screen)
  end, "cmd+shift+e did not open the explorer")
  local seen = {}
  for _ = 1, 4 do
    press(screen, "<D-b>")
    screen:flush()
    vim.wait(400, function()
      return false
    end)
    seen[#seen + 1] = explorer_open(screen)
  end
  lib.eq({ false, true, false, true }, seen, "cmd+b must toggle the explorer each time")

  press(screen, "<D-S-g>")
  vim.wait(500, function()
    return false
  end)
  local function git_hidden()
    return screen:exec("local v = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage()); return v and v.is_hidden == true")
  end
  lib.ok(not explorer_open(screen), "cmd+shift+g must close the explorer")
  local before = git_hidden()
  press(screen, "<D-b>")
  vim.wait(500, function()
    return false
  end)
  lib.ok(git_hidden() ~= before, "cmd+b must toggle the git pane after cmd+shift+g")
  lib.ok(not explorer_open(screen), "...and not open the explorer")
  screen:close()
end)
