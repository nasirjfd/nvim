local lib = require("lib")
local h = require("support")

lib.test("Git Shift+S offers to stage all before stashing when nothing is staged", function()
  local dir = h.repo({ ["a.txt"] = { "base" } })
  h.write(dir .. "/a.txt", { "changed" })
  h.write(dir .. "/new.txt", { "new file" })
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
        if node and node.data and node.data.type == "repository" then
          vim.api.nvim_set_current_win(p.winid)
          vim.api.nvim_win_set_cursor(p.winid, { line, 0 })
          return true
        end
      end
      return false
    ]])
  end, "Git pane did not load")
  local function open_confirmation()
    screen:input("S")
    h.wait(screen, function()
      return screen:exec([[
        return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
          :find("Stage all changes and stash?", 1, true) ~= nil
      ]])
    end, "stash did not offer the stage-all confirmation")
    lib.ok(h.find_on_screen(screen, "Stage all changes and stash?"), h.snapshot(screen))
  end
  open_confirmation()
  screen:input("n")
  h.wait(screen, function()
    return screen:exec([[
      local p = require("codediff.ui.lifecycle").get_panel_view(vim.api.nvim_get_current_tabpage())
      return vim.api.nvim_get_current_win() == p.winid
    ]])
  end, "cancel did not return to Git")
  lib.eq("", h.git(dir, "diff", "--cached", "--name-only"), "cancel must not stage")
  lib.eq("", h.git(dir, "stash", "list"), "cancel must not stash")
  open_confirmation()
  screen:input("y")
  h.wait(screen, function()
    return screen:exec(
      "return vim.bo.filetype == 'snacks_input' and vim.fn.mode():sub(1, 1) == 'i'"
    )
  end, "stash name prompt did not open")
  screen:input("saved changes<CR>")
  h.wait(screen, function()
    return h.git(dir, "stash", "list"):find("saved changes", 1, true) ~= nil
      and h.git(dir, "status", "--porcelain") == ""
  end, "confirmed changes were not stashed")
  lib.eq("", h.git(dir, "status", "--porcelain"), "all changes should be stashed")
  lib.eq("changed\n", h.git(dir, "show", "stash@{0}:a.txt"))
  lib.eq("new file\n", h.git(dir, "show", "stash@{0}:new.txt"))
  screen:close()
end)
