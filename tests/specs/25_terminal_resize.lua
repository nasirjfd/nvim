local lib = require("lib")
local h = require("support")

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
