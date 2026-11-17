local lib = require("lib")
local h = require("support")

lib.test("Escape is delivered to the topmost modal behind mouse focus", function()
  local screen = h.nvim(h.tmpdir())
  screen:exec([[
    vim.cmd("enew")
    local function modal(zindex, name)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { name })
      local win = vim.api.nvim_open_win(buf, false, {
        relative = "editor", row = 5, col = 30, width = 60, height = 20,
        border = "rounded", zindex = zindex,
      })
      vim.keymap.set("n", "<Esc>", function()
        vim.g["closed_" .. name] = true
        vim.api.nvim_win_close(win, true)
      end, { buffer = buf })
      return win
    end
    _G.lower_modal = modal(60, "lower")
    _G.upper_modal = modal(100, "upper")
  ]])
  screen:input("<Esc>")
  h.wait(screen, function()
    return screen:exec("return vim.g.closed_upper == true")
  end, "Escape did not reach the topmost modal")
  lib.ok(screen:exec("return vim.g.closed_lower ~= true"), "Escape reached a modal behind the topmost one")
  screen:close()
end)

lib.test("Escape closes the explorer keymap overlay without closing the explorer", function()
  local screen = h.nvim(h.tmpdir())
  screen:exec("Snacks.explorer()")
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'explorer' }) == 1")
  end, "explorer did not open")
  screen:input("?")
  h.wait(screen, function()
    return screen:exec([[
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "snacks_win_help" then return true end
      end
      return false
    ]])
  end, "explorer keymap overlay did not open")
  screen:input("<Esc>")
  h.wait(screen, function()
    return screen:exec([[
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "snacks_win_help" then return false end
      end
      return #Snacks.picker.get({ source = "explorer" }) == 1
    ]])
  end, "Escape did not close the explorer keymap overlay")
  screen:close()
end)

lib.test("Escape closes the tests-pane shortcut modal after returning to the pane", function()
  local screen = h.nvim(h.tmpdir())
  screen:exec([[
    local pane = require("modules.phpunit.pane")
    pane.toggle()
  ]])
  h.wait(screen, function()
    return screen:exec("return #require('modules.phpunit.pane').panes() == 1")
  end, "tests pane did not open")
  screen:input("?")
  h.wait(screen, function()
    return screen:exec([[
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "pane_shortcuts_help" then return true end
      end
      return false
    ]])
  end, "tests-pane shortcut modal did not open")
  screen:exec("require('modules.phpunit.pane').toggle()")
  screen:input("<Esc>")
  h.wait(screen, function()
    return screen:exec([[
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "pane_shortcuts_help" then return false end
      end
      return #require("modules.phpunit.pane").panes() == 1
    ]])
  end, "Escape did not close the tests-pane shortcut modal")
  screen:close()
end)
