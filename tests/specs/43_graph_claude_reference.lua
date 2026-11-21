local lib = require("lib")
local h = require("support")

lib.test(
  "Cmd+L sends the Git graph project and the selected row's branch through the normal Claude handoff",
  function()
    local dir = h.repo({ ["a.txt"] = { "base" } })
    h.git(dir, "checkout", "-qb", "feat/other")
    h.git(dir, "commit", "-q", "--allow-empty", "-m", "other work")
    h.git(dir, "checkout", "-qb", "feat/current", "HEAD~1")
    h.git(dir, "commit", "-q", "--allow-empty", "-m", "current work")
    local screen = h.nvim(dir)
    screen:exec([[
    vim.env.HERDR_PANE_ID = 'test-pane'
    local system = vim.system
    vim.system = function(cmd, opts, callback)
      if cmd[1]:match('/send%-ref%.sh$') then
        _G.sent_reference = cmd[2]
        callback({code=0, stdout='', stderr=''})
        return {}
      end
      return system(cmd, opts, callback)
    end
    vim.cmd('CodeDiff graph')
  ]])
    h.wait(screen, function()
      return screen:exec([[
      local g = require('codediff.ui.graph').get()
      return g and not g.loading and #g.commits > 0
    ]])
    end, "graph did not load")
    local project = vim.fn.fnamemodify(dir, ":t")
    screen:exec([[
    local g = require('codediff.ui.graph').get()
    for line, commit in ipairs(g.commits) do
      if commit.subject == 'current work' then
        vim.api.nvim_set_current_win(g.winid)
        vim.api.nvim_win_set_cursor(g.winid, {line, 0})
      end
    end
  ]])
    screen:input("<D-l>")
    h.wait(screen, function()
      return screen:exec("return _G.sent_reference ~= nil")
    end, "Cmd+L did not use the Claude handoff")
    lib.eq(project .. "->branch:feat/current ", screen:exec("return _G.sent_reference"))

    -- The selected row's branch, not the checked-out one.
    screen:exec([[
    local g = require('codediff.ui.graph').get()
    for line, commit in ipairs(g.commits) do
      if commit.subject == 'other work' then
        vim.api.nvim_set_current_win(g.winid)
        vim.api.nvim_win_set_cursor(g.winid, {line, 0})
      end
    end
    _G.sent_reference = nil
  ]])
    screen:input("<D-l>")
    h.wait(screen, function()
      return screen:exec("return _G.sent_reference ~= nil")
    end, "selected row's branch was not sent")
    lib.eq(project .. "->branch:feat/other ", screen:exec("return _G.sent_reference"))
    screen:exec([[
    vim.cmd('tabnew a.txt')
  ]])
    lib.eq("@a.txt#L1", screen:exec("return require('core.herdr-ref').reference(1, 1)"))
    screen:close()
  end
)
