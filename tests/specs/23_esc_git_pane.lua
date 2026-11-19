local lib = require("lib")
local h = require("support")

lib.test("Esc in the diff reaches the Git pane at once, not after timeoutlen", function()
  local lines = {}
  for i = 1, 30 do
    lines[i] = "line " .. i
  end
  local dir = h.repo({ ["a.txt"] = lines })
  lines[7] = "changed"
  h.write(dir .. "/a.txt", lines)
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit a.txt')")
  screen:exec("vim.cmd('CodeDiff scm')")
  h.wait(screen, function()
    return screen:exec([[
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      if not p or not p.tree then return false end
      for line = 1, vim.api.nvim_buf_line_count(p.bufnr) do
        local node = p.tree:get_node(line)
        if node and node.data and node.data.path == 'a.txt' then
          p.on_file_select(node.data)
          return true
        end
      end
      return false
    ]])
  end, "changed file did not appear in Git")
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      if not s or not s.stored_diff_result or not s.modified_win then return false end
      if s.refresh and (s.refresh.loading or s.refresh.running) then return false end
      vim.api.nvim_set_current_win(s.modified_win)
      return true
    ]])
  end, "diff did not load")
  screen:input("<Esc>")
  -- timeoutlen is 1000 ms: a lone Esc that waits for a longer mapping misses this limit
  h.wait(screen, function()
    return screen:exec([[
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      return vim.api.nvim_get_current_win() == p.split.winid
    ]])
  end, "Esc did not reach the Git pane within 500 ms", 500)
  screen:close()
end)
