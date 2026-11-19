local lib = require("lib")
local h = require("support")

-- Open a file, Cmd+Shift+G, `gl` to the graph, Cmd+Shift+G back: the file shown in the Git tab
-- (nothing selected) must not come back painted green as an added file.
lib.test("Returning from the graph to the Git pane leaves the open file undecorated", function()
  local dir = h.repo({ ["a.txt"] = { "one", "two" }, ["b.txt"] = { "bee" } })
  h.write(dir .. "/b.txt", { "changed" })
  local screen = h.nvim(dir, nil, nil, { "a.txt" })
  screen:input("<D-S-g>")
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      if vim.bo.filetype == 'codediff-explorer' and s and s.refresh and not s.refresh.loading then
        _G.git_tab = vim.api.nvim_get_current_tabpage()
        return true
      end
      return false
    ]])
  end, "Git pane did not open")
  screen:input("gl")
  h.wait(screen, function()
    return screen:exec(
      "return require('codediff.ui.graph').get(vim.api.nvim_get_current_tabpage()) ~= nil"
    )
  end, "gl did not open the graph")
  screen:input("<D-S-g>")
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(_G.git_tab)
      return vim.api.nvim_get_current_tabpage() == _G.git_tab and s and not s.suspended
    ]])
  end, "Cmd+Shift+G did not return to the Git pane")
  vim.wait(300) -- nothing else may paint the file afterwards
  lib.eq(
    0,
    screen:exec([[
      local ns = vim.api.nvim_get_namespaces()['codediff-highlight']
      return #vim.api.nvim_buf_get_extmarks(vim.fn.bufnr('a.txt'), ns, 0, -1, {})
    ]]),
    "a.txt is decorated as a diff"
  )
  screen:close()
end)
