-- Option+Cmd+Z reverts the hunk under the cursor in a diff tab, and only that hunk.
local lib = require("lib")
local h = require("support")

lib.test("cmd+alt+z reverts only the hunk under the cursor in a working-tree diff", function()
  local base = {}
  for i = 1, 40 do
    base[i] = "line " .. i
  end
  local dir = h.repo({ ["a.txt"] = base })
  local changed = vim.deepcopy(base)
  changed[5], changed[30] = "CHANGED 5", "CHANGED 30"
  h.write(dir .. "/a.txt", changed)

  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit a.txt'); vim.cmd('CodeDiff')")
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      return s ~= nil and s.stored_diff_result ~= nil and s.stored_diff_result.changes ~= nil and #s.stored_diff_result.changes == 2
    ]])
  end, "the diff never opened")
  screen:exec([[
    local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
    vim.api.nvim_set_current_win(s.modified_win)
    vim.api.nvim_win_set_cursor(s.modified_win, { 5, 0 })
    vim.fn.maparg('<D-M-z>', 'n', false, true).callback()
  ]])
  h.wait(screen, function()
    return h.read(dir .. "/a.txt")[5] == "line 5"
  end, "the hunk under the cursor was not reverted")
  lib.eq("CHANGED 30", h.read(dir .. "/a.txt")[30], "the other hunk must stay")
  screen:close()
end)
