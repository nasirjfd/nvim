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
