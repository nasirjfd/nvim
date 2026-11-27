local lib = require("lib")
local h = require("support")

lib.test("Git Enter preserves the current file position but jumps from the beginning", function()
  local lines = {}
  for i = 1, 100 do
    lines[i] = "line " .. i
  end
  local dir = h.repo({ ["a.txt"] = lines })
  lines[12] = "first change"
  lines[65] = "later change"
  h.write(dir .. "/a.txt", lines)
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit a.txt'); vim.cmd('CodeDiff scm')")
  h.wait(screen, function()
    return screen:exec([[
      local l = require("codediff.ui.lifecycle")
      local tab = vim.api.nvim_get_current_tabpage()
      local p, s = l.get_panel_view(tab), l.get_session(tab)
      if not p or not p.tree or not s or not s.stored_diff_result then return false end
      if s.refresh and (s.refresh.loading or s.refresh.running) then return false end
      for line = 1, vim.api.nvim_buf_line_count(p.bufnr) do
        local node = p.tree:get_node(line)
        if node and node.data and node.data.path == "a.txt" then
          vim.api.nvim_win_set_cursor(p.winid, { line, 0 })
          return true
        end
      end
      return false
    ]])
  end, "Git diff did not load")

  local function enter_from(line, col)
    screen:exec([[
      local l = require("codediff.ui.lifecycle")
      local tab = vim.api.nvim_get_current_tabpage()
      local s = l.get_session(tab)
      vim.api.nvim_set_current_win(s.modified_win)
    ]])
    screen:input(tostring(line) .. "G0" .. (col > 0 and tostring(col) .. "l" or ""))
    h.wait(screen, function()
      return screen:exec(([[
        local pos = vim.api.nvim_win_get_cursor(0)
        return pos[1] == %d and pos[2] == %d
      ]]):format(line, col))
    end, "could not move to the file position")
    screen:input("<Esc>")
    h.wait(screen, function()
      return screen:exec([[
        local p = require("codediff.ui.lifecycle").get_panel_view(vim.api.nvim_get_current_tabpage())
        return vim.api.nvim_get_current_win() == p.winid
      ]])
    end, "Esc did not focus Git")
    screen:input("<CR>")
  end

  local function landed(line, col)
    h.wait(screen, function()
      return screen:exec(([[
        local s = require("codediff.ui.lifecycle").get_session(vim.api.nvim_get_current_tabpage())
        if s.refresh and (s.refresh.loading or s.refresh.running) then return false end
        local pos = vim.api.nvim_win_get_cursor(s.modified_win)
        return vim.api.nvim_get_current_win() == s.modified_win and pos[1] == %d and pos[2] == %d
      ]]):format(line, col))
    end, "Enter did not return to the expected file position")
  end

  enter_from(65, 4)
  landed(65, 4)
  enter_from(48, 2)
  landed(48, 2)
  enter_from(1, 0)
  landed(12, 0)
  screen:close()
end)
