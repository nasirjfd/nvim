local lib = require("lib")
local h = require("support")

local function panel(screen)
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      if s and s.panel and s.panel.data.kind == 'scm' and s.panel.view
        and s.refresh and not s.refresh.loading then
        _G.freshness_tab = vim.api.nvim_get_current_tabpage()
        return true
      end
      return false
    ]])
  end, "Git pane did not open")
end

local function listed(screen, path, present)
  h.wait(screen, function()
    return screen:exec(
      [[
      local path, present = ...
      local s = require('codediff.ui.lifecycle').get_session(_G.freshness_tab)
      local found = false
      for _, repo in ipairs(s.panel.data.repositories) do
        for _, group in ipairs({'unstaged','staged','conflicts'}) do
          for _, file in ipairs((repo.status_result or {})[group] or {}) do
            found = found or file.path == path
          end
        end
      end
      return found == present
    ]],
      { path, present }
    )
  end, "Git pane stale for " .. path)
end

for _, opening in ipairs({ "shortcut", "command" }) do
  lib.test("Git pane reads autosaved edits before its first status via " .. opening, function()
    local dir = h.repo({ ["a.txt"] = { "base" }, ["other.txt"] = { "other" } })
    local screen = h.nvim(dir, nil, nil, { "a.txt" })
    screen:exec([[
      require('lazy').load({plugins={'multi-repo-code-diff'}})
      local view = require('codediff.ui.view')
      local create = view.create
      view.create = function(cfg, ...)
        if cfg.panel and cfg.panel.data.kind == 'scm' then
          _G.first_git_status = vim.deepcopy(cfg.panel.data.repositories)
        end
        return create(cfg, ...)
      end
    ]])
    screen:input("rx") -- normal-mode edits have not fired InsertLeave/BufLeave
    lib.eq({ "base" }, h.read(dir .. "/a.txt"), "fixture was saved before the open")
    if opening == "shortcut" then
      screen:input("<D-S-g>")
    else
      screen:exec("vim.cmd('CodeDiff scm')")
    end
    panel(screen)
    lib.eq({ "xase" }, h.read(dir .. "/a.txt"), "opening Git did not flush autosave")
    lib.ok(
      screen:exec([[
      for _, repo in ipairs(_G.first_git_status or {}) do
        for _, file in ipairs((repo.status_result or {}).unstaged or {}) do
          if file.path == 'a.txt' then return true end
        end
      end
      return false
    ]]),
      "the initial pane status was read before autosave"
    )
    screen:close()
  end)
end

lib.test(
  "reopening Git immediately includes normal-mode autosave without a watcher delay",
  function()
    local dir = h.repo({ ["a.txt"] = { "base" } })
    local screen = h.nvim(dir, nil, nil, { "a.txt" })
    screen:input("<D-S-g>")
    panel(screen)
    screen:exec([[
    local s = require('codediff.ui.lifecycle').get_session(_G.freshness_tab)
    s.refresh.native=true; s.refresh.polling=false
    s.refresh.last_revalidate=vim.uv.now()
    vim.cmd.tabnew('a.txt')
  ]])
    screen:input("rx")
    lib.eq(
      "xase",
      screen:exec("return vim.api.nvim_get_current_line()"),
      "fixture edit did not land in the editor"
    )
    screen:input("<D-S-g>")
    h.wait(screen, function()
      return screen:exec("return vim.api.nvim_get_current_tabpage() == _G.freshness_tab")
    end, "Git shortcut did not return to its pane")
    lib.eq({ "xase" }, h.read(dir .. "/a.txt"), "reopening Git did not flush autosave")
    listed(screen, "a.txt", true)
    screen:close()
  end
)

lib.test(
  "external nested changes refresh hidden Git panes even when native notifications are missed",
  function()
    local dir = h.repo({ ["a.txt"] = { "base" } })
    local screen = h.nvim(dir)
    screen:exec([[
    require('lazy').load({plugins={'multi-repo-code-diff'}})
    require('codediff.config').options.scm.reconcile_interval=60000
    require('codediff.config').options.scm.auto_fetch=false
    local watcher=require('codediff.core.watcher')
    local subscribe=watcher.subscribe
    watcher.subscribe=function(root, handlers)
      handlers.on_refresh=function() end
      return subscribe(root, handlers)
    end
    vim.cmd('CodeDiff scm')
  ]])
    panel(screen)
    h.wait(screen, function()
      return screen:exec([[
      local c=require('codediff.ui.lifecycle').get_session(_G.freshness_tab).refresh
      return c.native and not c.running and not c.loading and not next(c.pending)
    ]])
    end, "Git watcher did not become ready")
    screen:exec("vim.cmd.tabnew()")
    local away = screen:exec("return vim.api.nvim_get_current_tabpage()")
    h.write(dir .. "/deep/new/agent.txt", { "external edit" })
    listed(screen, "deep/new/agent.txt", true)
    lib.eq(
      away,
      screen:exec("return vim.api.nvim_get_current_tabpage()"),
      "background refresh stole focus"
    )
    vim.fn.delete(dir .. "/deep/new/agent.txt")
    listed(screen, "deep/new/agent.txt", false)
    screen:close()
  end
)

lib.test("opening Git respects autosave disabled and readonly buffers", function()
  local dir = h.repo({ ["a.txt"] = { "base" }, ["readonly.txt"] = { "original" } })
  local screen = h.nvim(dir, nil, nil, { "a.txt" })
  screen:exec([[
    vim.g.autosave=false
    vim.api.nvim_buf_set_lines(0,0,-1,false,{'unsaved'})
    require('core.autosave').flush()
    _G.autosave_disabled_respected = vim.fn.readfile('a.txt')[1] == 'base'
    vim.cmd.edit('readonly.txt')
    vim.bo.readonly=true
    vim.api.nvim_buf_set_lines(0,0,-1,false,{'do not write'})
    vim.g.autosave=true
    require('core.autosave').flush()
  ]])
  -- The ordinary writable buffer is saved; readonly content must never be forced.
  lib.ok(screen:exec("return _G.autosave_disabled_respected"), "autosave disabled was ignored")
  lib.eq({ "unsaved" }, h.read(dir .. "/a.txt"))
  lib.eq({ "original" }, h.read(dir .. "/readonly.txt"))
  screen:close()
end)
