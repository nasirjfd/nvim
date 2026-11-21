local lib = require("lib")
local h = require("support")

local function conflict_repo(first)
  first = first or 6
  local base = {}
  for i = 1, 70 do base[i] = "context " .. i end
  base[first], base[45] = "base-one", "base-two"
  local dir = h.repo({ ["merge.txt"] = base })
  h.git(dir, "checkout", "-qb", "incoming")
  local theirs = vim.deepcopy(base)
  theirs[first], theirs[45] = "theirs-one", "theirs-two"
  h.write(dir .. "/merge.txt", theirs)
  h.git(dir, "commit", "-qam", "incoming changes")
  h.git(dir, "checkout", "-q", "main")
  local ours = vim.deepcopy(base)
  ours[first], ours[45] = "ours-one", "ours-two"
  h.write(dir .. "/merge.txt", ours)
  h.git(dir, "commit", "-qam", "local changes")
  local result = vim.system({ "git", "-C", dir, "merge", "incoming", "--no-edit" }, { text = true }):wait()
  lib.eq(1, result.code, "fixture did not create real conflicts")
  return dir, base
end

lib.test("rapid merge arrow clicks from the sidebar apply both blocks without opening another change", function()
  local dir, base = conflict_repo(20)
  local screen = h.nvim(dir, 220, 30)
  screen:exec("vim.cmd('edit merge.txt'); vim.cmd('CodeDiff -- merge.txt')")
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      return s and s.conflict_blocks and #s.conflict_blocks == 2
        and s.refresh and not s.refresh.loading and not s.refresh.running
    ]])
  end, "merge view did not open")
  local expected = vim.deepcopy(base)
  local previous_position
  for index, line in ipairs({20, 45}) do
    screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      vim.api.nvim_set_current_win(s.original_win)
      vim.api.nvim_win_set_cursor(s.original_win, {...,0})
      vim.cmd('normal! zz')
    ]], {line})
    local value = index == 1 and "ours-one" or "ours-two"
    -- the panes follow the scroll on WinScrolled, which tells them which pane was scrolled: let that run
    -- before the focus moves to the sidebar (on a busy machine it came after, and the panes went back)
    h.wait(screen, function()
      return h.find_on_screen(screen, value) ~= nil
    end, "target conflict was not visible")
    screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      vim.api.nvim_set_current_win(s.panel.view.winid)
    ]])
    h.wait(screen, function()
      return h.find_on_screen(screen, value) ~= nil
    end, "target conflict was not visible")
    local row = h.find_on_screen(screen, value)
    local col = h.find_on_row(screen, row, "→")
    lib.ok(col ~= nil, "target arrow was not visible")
    if previous_position then
      lib.eq(previous_position, {row,col}, "regression must click the same screen cell rapidly")
    end
    previous_position = {row,col}
    h.click(screen,row,col)
    expected[line] = value
    h.wait(screen, function()
      return vim.deep_equal(expected, screen:exec([[
        local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
        return vim.api.nvim_buf_get_lines(s.result_bufnr,0,-1,false)
      ]]))
    end, "rapid arrow click reactivated the sidebar instead of applying the targeted block")
    lib.eq("codediff-explorer", screen:exec("return vim.bo.filetype"), "arrow click stole focus")
  end
  screen:close()
end)

for _, side in ipairs({ "left", "right" }) do
  lib.test("real mouse " .. side .. " merge arrow applies the clicked conflict without jumping", function()
    local dir, base = conflict_repo()
    local screen = h.nvim(dir, 220, 50)
    screen:exec("vim.cmd('edit merge.txt'); vim.cmd('CodeDiff -- merge.txt')")
    h.wait(screen, function()
      return screen:exec([[
        local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
        return s and s.merge and s.conflict_blocks and #s.conflict_blocks == 2
          and s.refresh and not s.refresh.loading and not s.refresh.running
      ]])
    end, "real merge view did not open")
    screen:flush()
    local text = side == "left" and "ours-one" or "theirs-one"
    local row = h.find_on_screen(screen, text)
    lib.ok(row ~= nil, "merge side is not visible")
    local glyph = side == "left" and "→" or "←"
    local col = h.find_on_row(screen, row, glyph)
    lib.ok(col ~= nil, "merge arrow is not visible")
    h.click(screen, row, col)
    local expected = vim.deepcopy(base)
    expected[6] = text
    h.wait(screen, function()
      return vim.deep_equal(expected, screen:exec([[
        local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
        return vim.api.nvim_buf_get_lines(s.result_bufnr,0,-1,false)
      ]]))
    end, function()
      return "click did not apply exactly one conflict: " .. screen:exec([[
        local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
        return vim.inspect({lines=vim.api.nvim_buf_get_lines(s.result_bufnr,0,-1,false), mouse=vim.fn.getmousepos(), error=vim.v.errmsg,
          map=vim.fn.maparg('<LeftMouse>', 'n', false, true)})
      ]])
    end)
    screen:close()
  end)
end

-- nvim-scrollbar draws a clickable one-column float over the last column of every pane, and a click on
-- it scrolls the file to that point. The left column's buttons are right-aligned: they must stop before
-- it, or a click on the right edge of → jumped somewhere in the file instead of taking the side.
lib.test("left merge buttons stay clear of the scrollbar: every cell of → takes the side without scrolling", function()
  local dir, base = conflict_repo(20)
  local screen = h.nvim(dir, 220, 30)
  screen:exec("vim.cmd('edit merge.txt'); vim.cmd('CodeDiff -- merge.txt')")
  local session = "require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())"
  h.wait(screen, function()
    return screen:exec("local s = " .. session .. [[
      return s and s.merge and s.conflict_blocks and #s.conflict_blocks == 2
        and s.refresh and not s.refresh.loading and not s.refresh.running
    ]])
  end, "merge view did not open")
  local left = screen:exec("local s = " .. session .. [[
    local p = vim.api.nvim_win_get_position(s.original_win)
    return { col = p[2] + 1, width = vim.api.nvim_win_get_width(s.original_win), win = s.original_win }
  ]])
  local last_col = left.col + left.width - 1
  -- the scrollbar float is there, on the left column's last column
  h.wait(screen, function()
    return screen:exec([[
      local win, col = ...
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local c = vim.api.nvim_win_get_config(w)
        if c.relative ~= '' and vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'scrollbar'
          and vim.api.nvim_win_get_position(w)[2] + 1 == col then
          return true
        end
      end
      return false
    ]], { left.win, last_col })
  end, "no scrollbar float on the left column's last column")
  local row
  h.wait(screen, function()
    row = h.find_on_screen(screen, "ours-one")
    return row ~= nil and h.find_on_row(screen, row, "→") ~= nil
  end, "the left arrow is not visible")
  local col = h.find_on_row(screen, row, "→")
  -- " → " is the button: all three cells left of the scrollbar column
  lib.ok(col + 1 < last_col, ("the → button reaches the scrollbar column (%d, %d)"):format(col, last_col))
  local top = function()
    return screen:exec("local s = " .. session .. " return vim.api.nvim_win_call(s.original_win, vim.fn.winsaveview).topline")
  end
  local before = top()
  h.click(screen, row, col + 1)
  local expected = vim.deepcopy(base)
  expected[20] = "ours-one"
  h.wait(screen, function()
    return vim.deep_equal(expected, screen:exec("local s = " .. session .. " return vim.api.nvim_buf_get_lines(s.result_bufnr, 0, -1, false)"))
  end, "a click on the right edge of → did not take the side")
  lib.eq(before, top(), "the click scrolled the left column")
  screen:close()
end)
