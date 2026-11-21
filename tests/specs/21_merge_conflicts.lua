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

-- Merge & next (the middle button under the Result): a box asks when conflicts are left (never the
-- command line, which grew and pushed the view up and down), no dialog over the view, and the next
-- file comes in one redraw: never its sides next to the old Result, never without its column headers
-- and buttons, never before the scroll to its conflict. The last file ends in the box to commit.
lib.test("Merge & next goes to the next conflicted file in one redraw, without prompts in the command line", function()
  local function numbered(word)
    local lines = {}
    for i = 1, 60 do
      lines[i] = word .. " " .. i
    end
    return lines
  end
  local a, b = numbered("alpha"), numbered("bravo")
  local dir = h.repo({ ["a.txt"] = a, ["b.txt"] = b })
  h.git(dir, "checkout", "-qb", "topic")
  local ta, tb = vim.deepcopy(a), vim.deepcopy(b)
  ta[10], tb[45] = "alpha topic", "bravo topic"
  h.write(dir .. "/a.txt", ta)
  h.write(dir .. "/b.txt", tb)
  h.git(dir, "commit", "-qam", "topic")
  h.git(dir, "checkout", "-q", "main")
  local ma, mb = vim.deepcopy(a), vim.deepcopy(b)
  ma[10], mb[45] = "alpha main", "bravo main"
  h.write(dir .. "/a.txt", ma)
  h.write(dir .. "/b.txt", mb)
  h.git(dir, "commit", "-qam", "main")
  pcall(h.git, dir, "merge", "topic")

  local screen = h.nvim(dir, 200, 40)
  screen:command("CodeDiff")
  local function merge_ready(name)
    return screen:exec(
      [[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      return s and s.merge and s.result_win and vim.api.nvim_win_is_valid(s.result_win) and s.conflict_blocks
        and #s.conflict_blocks > 0 and vim.api.nvim_buf_get_name(s.result_bufnr):sub(-#(...)) == (...)
        and vim.wo[s.original_win].winbar:find('Take all', 1, true) ~= nil
    ]],
      { name }
    )
  end
  h.wait(screen, function()
    return merge_ready("a.txt")
  end, "the merge view of a.txt did not open")
  local rows = screen:exec("return vim.o.lines - vim.o.cmdheight")

  -- every redraw from here on: what the three columns show
  screen:exec([[
    _G.redraws = {}
    vim.api.nvim_set_decoration_provider(vim.api.nvim_create_namespace('merge_next_redraws'), { on_end = function()
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      if not (s and s.result_win and vim.api.nvim_win_is_valid(s.result_win) and vim.api.nvim_win_is_valid(s.original_win)) then return end
      local function first(win)
        local top = vim.fn.line('w0', win)
        return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), top - 1, top, false)[1] or ''
      end
      local result = vim.api.nvim_win_get_buf(s.result_win)
      table.insert(_G.redraws, {
        side = first(s.original_win):match('^%a+'), result = first(s.result_win):match('^%a+'),
        header = vim.wo[s.original_win].winbar, conflict_shown = vim.fn.line('w0', s.result_win) > 1,
        result_name = vim.api.nvim_buf_get_name(result):match('[^/]+$'),
        floats = #vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative == 'editor' and vim.api.nvim_win_get_config(w).focusable end, vim.api.nvim_tabpage_list_wins(0)),
      })
    end })
  ]])

  -- a.txt still has its conflict: a box asks, the command line stays one row
  screen:exec("require('codediff.ui.conflict.bar').press(vim.api.nvim_get_current_tabpage(), 'merge_next')")
  h.wait(screen, function()
    return h.find_on_screen(screen, "1 conflict is left in a.txt. Merge it anyway?") ~= nil
  end, "Merge & next did not ask in a box")
  lib.eq(rows, screen:exec("return vim.o.lines - vim.o.cmdheight"))
  screen:input("y")
  h.wait(screen, function()
    return merge_ready("b.txt") and h.find_on_screen(screen, "bravo main") ~= nil
  end, "Merge & next did not go to b.txt")
  vim.wait(400) -- the view settles: nothing else may change it
  lib.eq("b.txt", vim.trim(h.git(dir, "diff", "--name-only", "--diff-filter=U")))

  local redraws = screen:exec("return _G.redraws")
  for index, frame in ipairs(redraws) do
    local where = ("redraw %d: %s"):format(index, vim.inspect(frame))
    if frame.side == "bravo" or frame.result == "bravo" then
      lib.eq(frame.side, frame.result, "the sides and the Result show different files, " .. where)
      lib.ok(frame.header:find("Take all", 1, true), "b.txt without its column header buttons, " .. where)
      lib.ok(frame.conflict_shown, "b.txt before the scroll to its conflict, " .. where)
    end
    lib.ok(frame.floats <= 1, "a dialog over the merge view, " .. where)
  end
  lib.ok(not h.find_on_screen(screen, "conflicted file"), "the conflict list dialog opened over the view")

  -- the last file: once resolved, Merge & next offers to commit the merge in a box
  screen:exec([[
    local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
    vim.api.nvim_set_current_win(s.result_win)
    require('codediff.ui.conflict.bar').press(vim.api.nvim_get_current_tabpage(), 'merge_next')
  ]])
  h.wait(screen, function()
    return h.find_on_screen(screen, "1 conflict is left in b.txt. Merge it anyway?") ~= nil
  end, "Merge & next on the last file did not ask in a box")
  screen:input("y")
  h.wait(screen, function()
    return h.find_on_screen(screen, "Commit the merge?") ~= nil
  end, "the last Merge & next did not offer to commit the merge")
  lib.eq(rows, screen:exec("return vim.o.lines - vim.o.cmdheight"))
  screen:input("y")
  h.wait(screen, function()
    return h.git(dir, "log", "-1", "--format=%P"):find(" ") ~= nil
  end, "the merge was not committed")
  screen:close()
end)
