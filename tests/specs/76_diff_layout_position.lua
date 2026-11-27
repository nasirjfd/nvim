local lib = require("lib")
local h = require("support")

lib.test("Git t keeps the cursor and viewport across committed diff layouts", function()
  local lines = {}
  for i = 1, 160 do
    lines[i] = "line " .. i .. " with enough text"
  end
  local dir = h.repo({ ["a.txt"] = lines })
  lines[12], lines[110] = "first change", "later change with enough text"
  table.insert(lines, 25, "added line one")
  table.insert(lines, 26, "added line two")
  h.write(dir .. "/a.txt", lines)
  h.git(dir, "add", "a.txt")
  h.git(dir, "commit", "-qm", "changed")
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit a.txt'); vim.cmd('CodeDiff HEAD~1 HEAD')")
  h.wait(screen, function()
    return screen:exec([[
      local s = require("codediff.ui.lifecycle").get_session(vim.api.nvim_get_current_tabpage())
      if not s or not s.stored_diff_result or #(s.stored_diff_result.changes or {}) ~= 3 then return false end
      if vim.api.nvim_buf_line_count(s.modified_bufnr) ~= 162 then return false end
      if s.refresh and (s.refresh.loading or s.refresh.running) then return false end
      vim.api.nvim_set_current_win(s.modified_win)
      return true
    ]])
  end, "Git diff did not load")
  screen:input("112G04lzt")
  h.wait(screen, function()
    return screen:exec("local p = vim.api.nvim_win_get_cursor(0); return p[1] == 112 and p[2] == 4")
  end, "could not move to later change")
  local top = screen:exec("return vim.fn.winsaveview().topline")
  for _, layout in ipairs({ "inline", "side-by-side", "inline", "side-by-side" }) do
    screen:input("t")
    h.wait(screen, function()
      return screen:exec(([[
        local s = require("codediff.ui.lifecycle").get_session(vim.api.nvim_get_current_tabpage())
        if not s or s.layout ~= %q then return false end
        if s.refresh and (s.refresh.loading or s.refresh.running) then return false end
        return s.stored_diff_result ~= nil
      ]]):format(layout))
    end, "layout did not finish toggling")
    local pos = screen:exec("return vim.api.nvim_win_get_cursor(0)")
    lib.eq({ 112, 4 }, pos, "t must keep the current line and column in " .. layout)
    lib.eq(top, screen:exec("return vim.fn.winsaveview().topline"), "t must keep the viewport")
  end
  screen:close()
end)
