local lib = require("lib")
local h = require("support")

lib.test("graph focused j and k follow branch history with the installed plugin", function()
  local dir = h.repo({ ["base.txt"] = { "base" } })
  h.git(dir, "checkout", "-qb", "feature")
  h.write(dir .. "/side.txt", { "side" })
  h.git(dir, "add", ".")
  h.git(dir, "commit", "-qm", "side work")
  h.git(dir, "checkout", "-q", "main")
  h.write(dir .. "/main.txt", { "main" })
  h.git(dir, "add", ".")
  h.git(dir, "commit", "-qm", "main work")
  h.git(dir, "merge", "-q", "--no-ff", "-m", "merge feature", "feature")
  h.write(dir .. "/latest.txt", { "latest" })
  h.git(dir, "add", ".")
  h.git(dir, "commit", "-qm", "latest")
  local screen = h.nvim(dir, 180, 45, { "base.txt" })
  screen:exec([[
    require('codediff').setup({graph={page_size=2, load_more_margin=0}})
    vim.cmd('CodeDiff graph')
  ]])
  h.wait(screen, function()
    return screen:exec([[
      local g = require('codediff.ui.graph').get()
      return g and not g.loading and #g.commits == 2
    ]])
  end, "graph did not open")
  screen:input("sjjj")
  h.wait(screen, function()
    return screen:exec([[
      local g = require('codediff.ui.graph').get()
      local row = vim.api.nvim_win_get_cursor(g.winid)[1]
      return g.focus == 'main' and not g.loading and not g.focus_move
        and g.commits[row].subject == 'base'
    ]])
  end, "focused j did not reach main's base across pages")
  screen:input("3k")
  lib.eq(
    "latest",
    screen:exec([[
    local g = require('codediff.ui.graph').get()
    local row = vim.api.nvim_win_get_cursor(g.winid)[1]
    return g.commits[row].subject
  ]]),
    "focused k did not return to main's tip"
  )
  screen:input("sj")
  lib.eq(
    2,
    screen:exec("return vim.api.nvim_win_get_cursor(0)[1]"),
    "leaving focus did not restore ordinary j"
  )
  screen:close()
end)
