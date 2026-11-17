local lib = require("lib")
local h = require("support")

lib.test(
  "Cmd+L sends the Git graph project and branch through the normal Claude handoff",
  function()
    local dir = h.repo({ ["a.txt"] = { "base" } })
    h.git(dir, "checkout", "-qb", "feat/current")
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
    screen:input("<D-l>")
    h.wait(screen, function()
      return screen:exec("return _G.sent_reference ~= nil")
    end, "Cmd+L did not use the Claude handoff")
    lib.eq(
      "Project: " .. project .. "\nBranch: feat/current ",
      screen:exec("return _G.sent_reference")
    )

    screen:exec([[
    require('codediff.ui.graph').get().filters.branch = {'feat/selected'}
    _G.sent_reference = nil
  ]])
    screen:input("<D-l>")
    h.wait(screen, function()
      return screen:exec("return _G.sent_reference ~= nil")
    end, "selected graph branch was not sent")
    lib.eq(
      "Project: " .. project .. "\nBranch: feat/selected ",
      screen:exec("return _G.sent_reference")
    )
    screen:exec([[
    vim.cmd('tabnew a.txt')
  ]])
    lib.eq("@a.txt#L1", screen:exec("return require('core.herdr-ref').reference(1, 1)"))
    screen:close()
  end
)
