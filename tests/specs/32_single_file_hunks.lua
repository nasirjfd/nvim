local lib = require("lib")
local h = require("support")

for _, mode in ipairs({ "Git pane", "commit page" }) do
  lib.test("F7 completes the wrap countdown with one changed file in the " .. mode, function()
    local lines = {}
    for i = 1, 50 do
      lines[i] = "line " .. i
    end
    local dir = h.repo({ ["a.txt"] = lines })
    lines[7], lines[40] = "first change", "last change"
    h.write(dir .. "/a.txt", lines)
    if mode == "commit page" then
      h.git(dir, "commit", "-qam", "two changes in one file")
    end
    local screen = h.nvim(dir)
    screen:exec("vim.cmd('edit a.txt')")
    if mode == "Git pane" then
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
    else
      screen:exec("vim.cmd('CodeDiff graph')")
      h.wait(screen, function()
        return screen:exec([[
          local g = require('codediff.ui.graph').get(vim.api.nvim_get_current_tabpage())
          return g and g.details and next(g.details.files or {}) ~= nil
        ]])
      end, "commit details did not load")
      screen:input("<CR><CR>")
    end
    h.wait(screen, function()
      return screen:exec([[
        local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
        if not s or not s.stored_diff_result or not s.stored_diff_result.changes or #s.stored_diff_result.changes ~= 2 then return false end
        if s.refresh and (s.refresh.loading or s.refresh.running) then return false end
        _G.single_file_session = s
        vim.api.nvim_set_current_win(s.modified_win)
        return true
      ]])
    end, "single-file diff did not load")
    screen:exec("vim.api.nvim_win_set_cursor(0, {7, 0})")
    screen:input("<F7>")
    h.wait(screen, function()
      return screen:exec("return vim.api.nvim_win_get_cursor(0)[1] == 40")
    end, "F7 did not reach the last hunk")
    screen:input("<F7>")
    for left = 4, 1, -1 do
      screen:input("<F7>")
      lib.eq(
        { 40, left },
        screen:exec(
          "return {vim.api.nvim_win_get_cursor(0)[1], _G.single_file_session.end_armed.left}"
        ),
        "the countdown wrapped too early"
      )
    end
    screen:input("<F7>")
    h.wait(screen, function()
      return screen:exec([[
        local s = _G.single_file_session
        return vim.api.nvim_win_get_cursor(s.modified_win)[1] == 7
          and vim.api.nvim_win_get_cursor(s.original_win)[1] == 7
          and s.end_armed == nil and s.pending_cursor_landing == nil
      ]])
    end, "F7 did not return both diff panes to the first hunk")
    screen:input("<F7>")
    h.wait(screen, function()
      return screen:exec("return vim.api.nvim_win_get_cursor(0)[1] == 40")
    end, "F7 stopped working after wrapping")
    screen:close()
  end)
end
