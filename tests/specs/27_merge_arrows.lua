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
      vim.api.nvim_set_current_win(s.panel.view.winid)
    ]], {line})
    screen:flush()
    local value = index == 1 and "ours-one" or "ours-two"
    local row = h.find_on_screen(screen, value)
    lib.ok(row ~= nil, "target conflict was not visible")
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
