local lib = require("lib")
local h = require("support")

for _, pane in ipairs({ "panel", "original", "modified" }) do
  lib.test("Escape returns from a commit diff " .. pane .. " to its graph details (a diff side through its file list)", function()
    local dir = h.repo({ ["a.txt"] = { "one" }, ["b.txt"] = { "two" } })
    h.write(dir .. "/a.txt", { "changed one" })
    h.write(dir .. "/b.txt", { "changed two" })
    h.git(dir, "commit", "-qam", "change both files")
    local screen = h.nvim(dir)
    screen:exec("vim.cmd('CodeDiff graph')")
    h.wait(screen, function()
      return screen:exec([[
      local g = require('codediff.ui.graph').get(vim.api.nvim_get_current_tabpage())
      return g and g.details and next(g.details.files or {}) ~= nil
    ]])
    end, "Graph details did not load")
    screen:input("<CR>")
    h.wait(screen, function()
      return screen:exec("return vim.bo.filetype == 'codediff-graph-details'")
    end, "Enter did not focus commit details")
    screen:exec("_G.graph_tab = vim.api.nvim_get_current_tabpage()")
    screen:input("<CR>")
    h.wait(screen, function()
      return screen:exec([[
      local tab = vim.api.nvim_get_current_tabpage()
      local s = require('codediff.ui.lifecycle').get_session(tab)
      return tab ~= _G.graph_tab and s and s.back and s.original_bufnr
        and vim.api.nvim_buf_is_valid(s.original_bufnr)
        and vim.api.nvim_buf_get_name(s.original_bufnr):find('a.txt', 1, true) ~= nil
    ]])
    end, "Enter did not open the full commit diff")
    screen:exec(
      [[
    local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
    local pane = ...
    vim.api.nvim_set_current_win(pane == 'panel' and s.panel.view.winid or s[pane .. '_win'])
  ]],
      { pane }
    )
    local function where()
      return vim.inspect(screen:exec([[
      local map = vim.fn.maparg('<Esc>', 'n', false, true)
      return { ft = vim.bo.filetype, map = map.desc or map.rhs,
        tab = vim.api.nvim_get_current_tabpage(), graph = _G.graph_tab }
    ]]))
    end
    if pane ~= "panel" then
      -- from a diff side Esc goes to the commit's file list first, like the Source Control diff
      screen:exec("_G.diff_tab = vim.api.nvim_get_current_tabpage()")
      screen:input("<Esc>")
      h.wait(screen, function()
        return screen:exec([[
        local s = require('codediff.ui.lifecycle').get_session(_G.diff_tab)
        return vim.api.nvim_get_current_tabpage() == _G.diff_tab
          and vim.api.nvim_get_current_win() == s.panel.view.winid
      ]])
      end, function()
        return "Escape in a diff side did not go to the file list: " .. where()
      end)
    end
    screen:input("<Esc>")
    h.wait(screen, function()
      return screen:exec([[
      local g = require('codediff.ui.graph').get(_G.graph_tab)
      return vim.api.nvim_get_current_tabpage() == _G.graph_tab
        and vim.api.nvim_get_current_win() == g.details.winid
    ]])
    end, function()
      return "Escape did not return to commit details: " .. where()
    end)
    screen:close()
  end)
end

lib.test("Escape still keeps the regular Git sidebar open", function()
  local dir = h.repo({ ["a.txt"] = { "one" } })
  h.write(dir .. "/a.txt", { "changed" })
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('CodeDiff scm')")
  h.wait(screen, function()
    return screen:exec([[
      return vim.bo.filetype == 'codediff-explorer'
        and vim.fn.maparg('<Esc>', 'n', false, true).desc == 'Keep Git sidebar open'
    ]])
  end, "Git sidebar did not load")
  local tab = screen:exec("return vim.api.nvim_get_current_tabpage()")
  screen:input("<Esc>")
  lib.eq(tab, screen:exec("return vim.api.nvim_get_current_tabpage()"))
  lib.eq("codediff-explorer", screen:exec("return vim.bo.filetype"))
  screen:close()
end)
