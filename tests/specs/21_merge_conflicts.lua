local lib = require("lib")
local h = require("support")

lib.test("graph merge opens conflicts automatically and scrolls every merge pane", function()
  local base = {}
  for i = 1, 200 do
    base[i] = "line " .. i .. " " .. string.rep("long text ", 40)
  end
  local dir = h.repo({ ["f.txt"] = base })
  h.git(dir, "checkout", "-qb", "topic")
  local theirs = vim.deepcopy(base)
  theirs[20] = "topic conflict"
  h.write(dir .. "/f.txt", theirs)
  h.git(dir, "commit", "-qam", "topic work")
  h.git(dir, "checkout", "-q", "main")
  local ours = vim.deepcopy(base)
  ours[20] = "main conflict"
  h.write(dir .. "/f.txt", ours)
  h.git(dir, "commit", "-qam", "main work")

  local screen = h.nvim(dir, 220, 50)
  screen:exec("vim.cmd('CodeDiff graph')")
  h.wait(screen, function()
    return screen:exec([[
      local g = require('codediff.ui.graph').get()
      if not g or g.loading then return false end
      for row, text in ipairs(vim.api.nvim_buf_get_lines(g.bufnr, 0, -1, false)) do
        if text:find('topic work', 1, true) then
          vim.api.nvim_win_set_cursor(g.winid, {row, 0})
          return true
        end
      end
      return false
    ]])
  end, "Graph did not show the topic branch")
  screen:input("m")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_win_get_config(0).relative == 'editor'")
  end, "Merge confirmation did not open")
  screen:input("y")
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      return s and s.merge and s.result_win and s.conflict_blocks and #s.conflict_blocks > 0
    ]])
  end, "Merge conflict did not automatically open the three-way Git view")

  local wins = screen:exec([[
    local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
    return {s.original_win, s.result_win, s.modified_win}
  ]])
  local function wait_column(column)
    h.wait(screen, function()
      return screen:exec(
        [[
        local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
        local top
        for _, win in ipairs({s.original_win, s.result_win, s.modified_win}) do
          local v = vim.api.nvim_win_call(win, vim.fn.winsaveview)
          if v.leftcol ~= (...) then return false end
          local row = v.topline - v.topfill
          for anchor, count in pairs(require('codediff.ui.filler').get_virt_line_counts(vim.api.nvim_win_get_buf(win))) do
            if anchor < v.topline then row = row + count end
          end
          if top and top ~= row then return false end
          top = row
        end
        return true
      ]],
        { column }
      )
    end, "Merge panes did not scroll together to column " .. column)
  end
  for _, win in ipairs(wins) do
    screen:exec("vim.api.nvim_set_current_win(...)", { win })
    screen:input("40zl")
    wait_column(40)
    screen:input("5<C-e>")
    wait_column(40)
    screen:input("40zh")
    wait_column(0)
    local pos = screen:exec("return vim.api.nvim_win_get_position(...)", { win })
    screen:request("nvim_input_mouse", { "wheel", "right", "", 0, pos[1] + 5, pos[2] + 5 })
    wait_column(2)
    screen:request("nvim_input_mouse", { "wheel", "left", "", 0, pos[1] + 5, pos[2] + 5 })
    wait_column(0)
  end
  lib.eq("f.txt", vim.trim(h.git(dir, "diff", "--name-only", "--diff-filter=U")))
  screen:close()
end)
