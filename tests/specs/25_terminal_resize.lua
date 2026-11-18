local lib = require("lib")
local h = require("support")

lib.test("manual editor split sizes are not equalized by terminal resize", function()
  local screen = h.nvim(h.tmpdir(), 180, 45)
  local before = screen:exec([[
    vim.cmd('vsplit')
    _G.sized_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(_G.sized_win, 48)
    return vim.api.nvim_win_get_width(_G.sized_win)
  ]])
  screen:request("nvim_ui_try_resize", { 240, 60 })
  vim.wait(100)
  screen:request("nvim_ui_try_resize", { 180, 45 })
  vim.wait(100)
  local after = screen:exec("return vim.api.nvim_win_get_width(_G.sized_win)")
  lib.ok(math.abs(before - after) <= 2, "terminal resize reset the manually sized editor split")
  screen:close()
end)

for _, pane in ipairs({
  { source = "explorer", open = "Snacks.explorer()" },
  { source = "http_requests", open = "require('modules.http_requests').toggle()" },
  { source = "phpunit_tests", open = "require('modules.phpunit.pane').toggle()" },
}) do
  lib.test("manual " .. pane.source .. " pane width survives terminal resize", function()
    local dir = h.repo({ ["a.txt"] = { "one" }, ["a.http"] = { "GET https://example.com" } })
    local screen = h.nvim(dir, 180, 45)
    screen:exec("vim.cmd('edit a.txt'); " .. pane.open)
    h.wait(screen, function()
      return screen:exec("return #Snacks.picker.get({ source = ... }) == 1", { pane.source })
    end, "pane did not open")
    screen:exec([[
      local picker = Snacks.picker.get({ source = ... })[1]
      vim.api.nvim_win_set_width(picker.layout.root.win, 55)
    ]], { pane.source })
    vim.wait(100)
    for _ = 1, 3 do
      screen:request("nvim_ui_try_resize", { 240, 60 })
      vim.wait(100)
      screen:request("nvim_ui_try_resize", { 180, 45 })
      vim.wait(100)
      local width = screen:exec([[
        return vim.api.nvim_win_get_width(Snacks.picker.get({ source = ... })[1].layout.root.win)
      ]], { pane.source })
      lib.eq(55, width, "pane forgot the manually chosen width")
    end
    screen:exec("Snacks.picker.get({ source = ... })[1]:close()", { pane.source })
    h.wait(screen, function()
      return screen:exec("return #Snacks.picker.get({ source = ... }) == 0", { pane.source })
    end, "pane did not close")
    screen:exec(pane.open)
    h.wait(screen, function()
      return screen:exec("return #Snacks.picker.get({ source = ... }) == 1", { pane.source })
    end, "pane did not reopen")
    lib.eq(55, screen:exec([[
      return vim.api.nvim_win_get_width(Snacks.picker.get({ source = ... })[1].layout.root.win)
    ]], { pane.source }), "reopening the pane reset its width")
    screen:close()
  end)
end

lib.test("manual Git pane width survives refresh resize and toggling", function()
  local dir = h.repo({ ["a.txt"] = { "one", "two" } })
  local screen = h.nvim(dir, 180, 45)
  screen:exec("vim.cmd('edit a.txt'); vim.cmd('CodeDiff scm')")
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      -- open, and its first layout done: a drag before that is taken for the layout's own resizing
      local sizes = s and s.layout_sizes
      return s and s.panel and s.panel.view and s.panel.view.winid ~= nil
        and sizes and sizes.snapshot ~= nil and not sizes.structural
    ]])
  end, "Git pane did not open")
  screen:exec([[
    local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
    vim.api.nvim_win_set_width(p.winid, 55)
  ]])
  h.wait(screen, function() -- the drag is learned (on WinResized) before the terminal changes size
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      return s.layout_sizes and s.layout_sizes.panel_width == 55
    ]])
  end, "the Git pane's new width was not learned")
  for _, width in ipairs({ 240, 100, 180, 240, 180 }) do
    screen:request("nvim_ui_try_resize", { width, 45 })
    vim.wait(150)
    screen:exec([[
      local tab = vim.api.nvim_get_current_tabpage()
      require('codediff.ui.refresh').request(tab, { full = true, render = true })
      require('codediff.ui.layout').arrange(tab)
    ]])
    h.wait(screen, function()
      return screen:exec([[
        local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
        return vim.api.nvim_win_get_width(p.winid)
      ]]) == 55
    end, "Git pane reset its width")
  end
  screen:exec([[
    local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
    require('codediff.ui.explorer').toggle_visibility(p)
    require('codediff.ui.explorer').toggle_visibility(p)
  ]])
  lib.eq(55, screen:exec([[
    local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
    return vim.api.nvim_win_get_width(p.winid)
  ]]), "Git pane reset its width when reopened: " .. screen:exec([[
    local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
    return vim.inspect({sizes=s.layout_sizes, split=s.panel.view.split._size})
  ]]))
  screen:close()
end)

lib.test("terminal zoom resize preserves sidebar layout and command height", function()
  local dir = h.repo({ ["a.txt"] = { "one", "two" } })
  local screen = h.nvim(dir, 160, 45)
  screen:exec("vim.cmd('edit a.txt'); Snacks.explorer()")
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'explorer' }) == 1")
  end, "Explorer did not open")
  local explorer_tab = screen:exec("return vim.api.nvim_get_current_tabpage()")
  for _, key in ipairs({ "<D-S-e>", "<D-S-g>" }) do
    screen:exec("vim.fn.maparg(..., 'n', false, true).callback()", { key })
    h.wait(screen, function()
      return screen:exec([[
        if ... == '<D-S-e>' then
          return #Snacks.picker.get({ source = 'explorer' }) == 1
        end
        local l = package.loaded['codediff.ui.lifecycle']
        return l and l.get_panel_view(vim.api.nvim_get_current_tabpage()) ~= nil
          and #Snacks.picker.get({ source = 'explorer' }) == 0
      ]], { key })
    end, "requested sidebar did not open", 20000)
    for i = 1, 12 do
      screen:request("nvim_ui_try_resize", { 240, 65 })
      vim.wait(10)
      screen:request("nvim_ui_try_resize", { 100, 24 })
      vim.wait(10)
      screen:request("nvim_ui_try_resize", { 160, 45 })
      vim.wait(80)
      lib.eq(1, screen:exec("return vim.o.cmdheight"), "command area grew after resize " .. i)
      local state = screen:exec([[
        local lists, git = 0, 0
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
          lists = lists + (ft == 'snacks_picker_list' and 1 or 0)
          git = git + (ft == 'codediff-explorer' and 1 or 0)
        end
        return { lists, git }
      ]])
      lib.eq(key == "<D-S-e>" and { 1, 0 } or { 0, 1 }, state, "sidebars duplicated after resize")
      lib.eq(explorer_tab, screen:exec([[
        local picker = Snacks.picker.get({ source = 'explorer', tab = false })[1]
        return picker and vim.api.nvim_win_get_tabpage(picker.layout.root.win)
      ]]), "resize moved Explorer to another tab")
    end
  end
  screen:exec("vim.api.nvim_set_current_tabpage(...)", { explorer_tab })
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'explorer' }) == 1")
  end, "Explorer was lost on returning to its tab")
  screen:close()
end)
