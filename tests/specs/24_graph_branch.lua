local lib = require("lib")
local h = require("support")

lib.test("graph checkout offers the selected payment branch, not its CSAT descendant", function()
  local dir = h.repo({ ["a.txt"] = { "base" } })
  h.git(dir, "checkout", "-qb", "feat/post-payment")
  h.write(dir .. "/payment.txt", { "payment" })
  h.git(dir, "add", ".")
  h.git(dir, "commit", "-qm", "payment tip")
  local tip = vim.trim(h.git(dir, "rev-parse", "HEAD"))
  h.git(dir, "checkout", "-qb", "post-payment-csat")
  h.write(dir .. "/csat.txt", { "csat" })
  h.git(dir, "add", ".")
  h.git(dir, "commit", "-qm", "csat tip")
  local screen = h.nvim(dir, 180, 45, { "a.txt" })
  screen:exec("vim.cmd('CodeDiff graph')")
  h.wait(screen, function()
    return screen:exec(
      [[
      local g = require('codediff.ui.graph').get()
      if not g or g.loading or not g.details then return false end
      for row, commit in ipairs(g.commits) do
        if commit.hash == (...) then
          vim.api.nvim_win_set_cursor(g.winid, {row, 0})
          return true
        end
      end
      return false
    ]],
      { tip }
    )
  end, "payment branch did not load in the graph")
  screen:input("<Space>")
  h.wait(screen, function()
    return screen:exec([[
      local p = Snacks.picker.get({source='select'})[1]
      return p and #p:items() == 1 and p:items()[1].item.name == 'feat/post-payment'
    ]])
  end, "checkout picker offered the descendant instead of feat/post-payment")
  screen:input("<CR>")
  h.wait(screen, function()
    return vim.trim(h.git(dir, "branch", "--show-current")) == "feat/post-payment"
  end, "checkout did not switch to the selected branch")
  lib.eq(tip, vim.trim(h.git(dir, "rev-parse", "HEAD")))
  screen:close()
end)

lib.test("branch lists are wide and show who made each branch's last commit", function()
  local dir = h.repo({ ["a.txt"] = { "base" } })
  h.git(dir, "checkout", "-qb", "feat/core-387-add-a-new-webhook-for-pickup-fail-webhook-retry")
  h.git(dir, "-c", "user.name=Grace Hopper", "commit", "-q", "--allow-empty", "-m", "side")
  h.git(dir, "checkout", "-q", "-")
  local screen = h.nvim(dir, 180, 45, { "a.txt" })
  screen:exec([[
    require("codediff.ui.explorer.actions").pick_branch(vim.fn.getcwd(), { prompt = "Squash which branch?", skip_current = true }, function() end)
  ]])
  h.wait(screen, function()
    return h.find_on_screen(screen, "just now · Grace Hopper") ~= nil
  end, "the branch row does not show its last commit's author")
  local width = screen:exec([[
    local p = Snacks.picker.get({ source = "select" })[1]
    return vim.api.nvim_win_get_width(p.list.win.win)
  ]])
  lib.ok(width >= 140, "the branch list is not wide: " .. width)
  screen:close()
end)
