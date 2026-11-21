local lib = require("lib")
local h = require("support")

lib.test("Git K expands only the selected file row over code with the same highlight", function()
  local name = "PublishSmsCommandsToMessageBrokerFromEventSubscription-long-name.php"
  local path = "src/long-directory/" .. name
  local dir = h.repo({ [path] = { "<?php", "old" }, ["other.txt"] = { "one" } })
  h.write(dir .. "/" .. path, { "<?php", "new" })
  local screen = h.nvim(dir, 240, 45)
  screen:exec("vim.cmd('edit ' .. vim.fn.fnameescape(...)); vim.cmd('CodeDiff scm')", { path })
  h.wait(screen, function()
    return screen:exec([[
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      if not p then return false end
      for line = 1, vim.api.nvim_buf_line_count(p.bufnr) do
        local node = p.tree:get_node(line)
        if node and node.data and node.data.path == ... then
          vim.api.nvim_set_current_win(p.winid)
          vim.api.nvim_win_set_cursor(p.winid, { line, 0 })
          _G.path_overlay_panel = p
          return true
        end
      end
      return false
    ]], { path })
  end, "file did not appear in Git")
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      return s and s.refresh and not s.refresh.loading and not s.refresh.running
    ]])
  end, "file preview did not settle")
  local before = screen:exec([[
    local win = _G.path_overlay_panel.winid
    return {win, vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_cursor(win)}
  ]])
  screen:input("K")
  h.wait(screen, function()
    return screen:exec("return _G.path_overlay_panel.path_overlay ~= nil")
  end, "K did not open the expanded file row")
  screen:flush()
  local row, col = h.find_on_screen(screen, name)
  lib.ok(row ~= nil, "the full filename is not visible on screen")
  lib.ok(col + #name > before[2], "the filename did not cross the sidebar boundary")
  local expected_bg = screen:exec("return vim.api.nvim_get_hl(0, {name='CodeDiffExplorerSelected', link=false}).bg")
  lib.eq(expected_bg, screen:highlight(row, col).background, "filename lost its selection highlight")
  lib.eq(expected_bg, screen:highlight(row, before[2] + 3).background, "extended row lost its selection highlight")
  lib.eq(before, screen:exec([[
    local win = _G.path_overlay_panel.winid
    return {vim.api.nvim_get_current_win(), vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_cursor(win)}
  ]]), "overlay changed the pane size, focus, or selection")
  lib.ok(screen:exec([[
    local buf = vim.api.nvim_win_get_buf(_G.path_overlay_panel.path_overlay.win)
    local text = vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]
    return text:find(" src/long-directory/", 1, true) ~= nil and not text:find(select(2, ...), 1, true)
  ]], { "", dir }), "the expanded row does not show the directory from the repository root")
  screen:input("K")
  h.wait(screen, function()
    return screen:exec("return _G.path_overlay_panel.path_overlay == nil")
  end, "second K did not close the row")
  screen:input("K")
  h.wait(screen, function()
    return screen:exec("return _G.path_overlay_panel.path_overlay ~= nil")
  end, "K did not reopen the row")
  screen:input("k")
  h.wait(screen, function()
    return screen:exec([[
      local overlay = _G.path_overlay_panel.path_overlay
      return overlay ~= nil and overlay.win == nil
    ]])
  end, "non-file row did not hide the overlay while keeping the mode enabled")
  screen:input("j")
  h.wait(screen, function()
    return screen:exec([[
      local overlay = _G.path_overlay_panel.path_overlay
      return overlay and overlay.win ~= nil and vim.api.nvim_win_is_valid(overlay.win)
    ]])
  end, "expanded-path mode did not follow the selected file")
  screen:input("K")
  h.wait(screen, function()
    return screen:exec("return _G.path_overlay_panel.path_overlay == nil")
  end, "K did not disable expanded-path mode")
  screen:close()
end)
