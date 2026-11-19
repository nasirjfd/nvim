local lib = require("lib")
local h = require("support")

lib.test("Cmd+J / Cmd+K go to the next / previous hunk in a file, like F7 / Shift+F7", function()
  local lines = {}
  for i = 1, 60 do
    lines[i] = "line " .. i
  end
  local dir = h.repo({ ["a.txt"] = lines })
  local changed = vim.deepcopy(lines)
  changed[10], changed[40] = "changed 10", "changed 40"
  h.write(dir .. "/a.txt", changed)
  local screen = h.nvim(dir)
  screen:exec(("vim.cmd.edit(%q)"):format(dir .. "/a.txt"))
  local function line()
    return screen:exec("return vim.api.nvim_win_get_cursor(0)[1]")
  end
  h.wait(screen, function()
    return screen:exec("return #(require('gitsigns').get_hunks() or {}) == 2")
  end, "gitsigns did not find the two hunks")
  screen:exec("vim.api.nvim_win_set_cursor(0, { 1, 0 })")
  screen:input("<D-j>")
  h.wait(screen, function()
    return line() == 10
  end, "Cmd+J did not reach the first hunk")
  screen:input("<D-j>")
  h.wait(screen, function()
    return line() == 40
  end, "Cmd+J did not reach the second hunk")
  screen:input("<D-k>")
  h.wait(screen, function()
    return line() == 10
  end, "Cmd+K did not go back to the first hunk")
  screen:close()
end)
