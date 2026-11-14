local lib = require("lib")
local h = require("support")

local function silent_pane(dir)
  local screen = h.nvim(dir)
  screen:exec([[
    require('lazy').load({ plugins = { 'multi-repo-code-diff' } })
    local options = require('codediff.config').options
    options.scm.auto_fetch = false
    options.scm.reconcile_interval = 250
    options.conflict.auto_open = false
    local watcher = require('codediff.core.watcher')
    local subscribe = watcher.subscribe
    watcher.subscribe = function(root, handlers)
      handlers.on_refresh = function() end
      return subscribe(root, handlers)
    end
    vim.cmd('CodeDiff scm')
  ]])
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      if not s or not s.refresh or not s.refresh.native or not s.panel or not s.panel.view then return false end
      _G.tracking_tab = vim.api.nvim_get_current_tabpage()
      return true
    ]])
  end, "Git pane and native watcher did not become ready")
  return screen
end

local function listed(screen, group, path)
  h.wait(screen, function()
    return screen:exec(
      [[
      local group, path = ...
      local panel = require('codediff.ui.lifecycle').get_session(_G.tracking_tab).panel
      for _, repo in ipairs(panel.data.repositories) do
        for _, file in ipairs(repo.status_result[group] or {}) do
          if file.path == path then
            local text = table.concat(vim.api.nvim_buf_get_lines(panel.view.bufnr, 0, -1, false), '\n')
            return text:find(vim.fn.fnamemodify(path, ':t'), 1, true) ~= nil
          end
        end
      end
      return false
    ]],
      { group, path }
    )
  end, "Git pane missed " .. group .. " file " .. path)
end

lib.test("Git pane recovers lost external-change events even while hidden", function()
  local dir = h.repo({ ["a.txt"] = { "base" } })
  local screen = silent_pane(dir)
  screen:command("tabnew")
  local away = screen:exec("return vim.api.nvim_get_current_tabpage()")
  h.write(dir .. "/deep/new/agent.txt", { "changed outside Neovim" })
  listed(screen, "unstaged", "deep/new/agent.txt")
  lib.eq(away, screen:exec("return vim.api.nvim_get_current_tabpage()"))
  screen:close()
end)

lib.test(
  "Git pane lists external merge conflicts without a restart or watcher notification",
  function()
    local dir = h.repo({ ["a.txt"] = { "base" } })
    h.git(dir, "checkout", "-qb", "topic")
    h.write(dir .. "/a.txt", { "topic" })
    h.git(dir, "commit", "-qam", "topic")
    h.git(dir, "checkout", "-q", "main")
    h.write(dir .. "/a.txt", { "main" })
    h.git(dir, "commit", "-qam", "main")
    local screen = silent_pane(dir)
    local merge = vim.system({ "git", "-C", dir, "merge", "topic", "--no-edit" }):wait()
    lib.eq(1, merge.code)
    listed(screen, "conflicts", "a.txt")
    lib.eq("a.txt", vim.trim(h.git(dir, "diff", "--name-only", "--diff-filter=U")))
    screen:close()
  end
)
