local lib = require("lib")
local h = require("support")

-- The file name at the left of the bottom row (lua/core/cmdline-file.lua) is a floating window, and a
-- floating window belongs to one tab: in a diff tab it must be there too, not only in the first tab
-- (there the diff's own "Hunk 1 of 1" message showed a name only until the cursor moved).
lib.test("the file name at the bottom left is shown in a diff tab and back in the first tab", function()
  local dir = h.repo({ ["a.txt"] = { "one", "two" }, ["b.txt"] = { "bee", "x", "y" } })
  h.write(dir .. "/b.txt", { "changed", "x", "y" })
  local screen = h.nvim(dir, nil, nil, { "a.txt" })
  local function bottom()
    return h.row_text(screen, screen.height)
  end
  h.wait(screen, function()
    return bottom():find("^a%.txt") ~= nil
  end, "no name in the first tab")
  screen:input("<D-S-g>")
  h.wait(screen, function()
    return screen:exec([[
      if vim.bo.filetype ~= 'codediff-explorer' then return false end
      for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
        if l:find('b.txt', 1, true) then vim.api.nvim_win_set_cursor(0, { i, 0 }) return true end
      end
      return false
    ]])
  end, "b.txt is not in the Git pane")
  screen:input("<CR>")
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      return s and s.modified_bufnr and vim.api.nvim_buf_get_name(s.modified_bufnr):find('b.txt', 1, true) ~= nil
        and s.refresh and not s.refresh.loading
    ]])
  end, "the diff of b.txt did not open")
  -- in the diff, after a move: the message is gone, the name stays
  screen:exec([[
    local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
    vim.api.nvim_set_current_win(s.modified_win)
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.cmd('echo ""')
  ]])
  h.wait(screen, function()
    return bottom():find("^b%.txt") ~= nil and not bottom():find("Hunk", 1, true)
  end, function()
    return "no name in the diff tab: " .. bottom()
  end)
  screen:input("gt")
  h.wait(screen, function()
    return bottom():find("^a%.txt") ~= nil
  end, function()
    return "no name back in the first tab: " .. bottom()
  end)
  screen:close()
end)
