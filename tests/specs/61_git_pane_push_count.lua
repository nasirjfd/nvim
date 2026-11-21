-- After a push, the pane's ↑N (commits ahead of the remote branch) goes away without waiting for the
-- next background fetch, whether the push came from the pane or from outside (a terminal, Claude).
local lib = require("lib")
local h = require("support")

local function ahead(screen)
  return screen:exec([[
    local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
    if not p or not p.tree then return -1 end
    for line = 1, vim.api.nvim_buf_line_count(p.bufnr) do
      local data = (p.tree:get_node(line) or {}).data or {}
      if data.type == 'repository' then return data.ahead or 0 end
    end
    return -1
  ]])
end

lib.test("the Git pane drops ↑1 after a push from outside Neovim", function()
  local remote = h.tmpdir()
  h.git(remote, "init", "-q", "--bare", "-b", "main")
  local dir = h.repo({ ["a.txt"] = { "one" } })
  h.git(dir, "remote", "add", "origin", remote)
  h.git(dir, "push", "-q", "-u", "origin", "main")
  h.write(dir .. "/a.txt", { "two" })
  h.git(dir, "commit", "-q", "-am", "second")
  local screen = h.nvim(dir)
  -- no background fetch: only the push itself may correct the count
  screen:exec("require('codediff.config').options.scm.auto_fetch = false; vim.cmd('CodeDiff scm')")
  h.wait(screen, function()
    return ahead(screen) == 1
  end, "the pane did not show ↑1 before the push")
  h.git(dir, "push", "-q", "origin", "main")
  h.wait(screen, function()
    return ahead(screen) == 0
  end, "the pane still shows ↑1 after the push", 8000)
  screen:close()
end)

-- Like supernova: listed repositories two folders down, a branch name with a slash (its remote
-- branch is a file in a sub folder of refs/remotes/origin).
lib.test("the Git pane drops ↑1 after a push in a listed repository on a feat/ branch", function()
  local top = h.tmpdir()
  local roots = {}
  for _, name in ipairs({ "org/one", "org/two" }) do
    local remote = h.tmpdir()
    h.git(remote, "init", "-q", "--bare", "-b", "main")
    local dir = top .. "/" .. name
    vim.fn.mkdir(dir, "p")
    h.git(dir, "init", "-q", "-b", "main")
    h.write(dir .. "/a.txt", { "one" })
    h.git(dir, "add", ".")
    h.git(dir, "commit", "-q", "-m", "base")
    h.git(dir, "remote", "add", "origin", remote)
    h.git(dir, "checkout", "-q", "-b", "feat/slash-branch")
    h.git(dir, "push", "-q", "-u", "origin", "feat/slash-branch")
    roots[#roots + 1] = dir
  end
  local dir = roots[2]
  h.write(dir .. "/a.txt", { "two" })
  h.git(dir, "commit", "-q", "-am", "second")
  local screen = h.nvim(top)
  screen:exec(
    [[
    local roots = ...
    require('codediff').setup({ scm = { only_listed = true, repositories = roots, auto_fetch = false } })
    vim.cmd('CodeDiff scm')
  ]],
    { roots }
  )
  local function count()
    return screen:exec([[
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      if not p or not p.tree then return -1 end
      for line = 1, vim.api.nvim_buf_line_count(p.bufnr) do
        local data = (p.tree:get_node(line) or {}).data or {}
        if data.type == 'repository' and data.name == 'two' then return data.ahead or 0 end
      end
      return -1
    ]])
  end
  h.wait(screen, function()
    return count() == 1
  end, "the pane did not show ↑1 before the push")
  h.git(dir, "push", "-q", "origin", "feat/slash-branch")
  h.wait(screen, function()
    return count() == 0
  end, "the pane still shows ↑1 after the push", 8000)
  screen:close()
end)

lib.test("the Git pane drops ↑1 for a push made while it was hidden", function()
  local remote = h.tmpdir()
  h.git(remote, "init", "-q", "--bare", "-b", "main")
  local dir = h.repo({ ["a.txt"] = { "one" } })
  h.git(dir, "remote", "add", "origin", remote)
  h.git(dir, "push", "-q", "-u", "origin", "main")
  h.write(dir .. "/a.txt", { "two" })
  h.git(dir, "commit", "-q", "-am", "second")
  local screen = h.nvim(dir)
  screen:exec("require('codediff.config').options.scm.auto_fetch = false; vim.cmd('CodeDiff scm')")
  h.wait(screen, function()
    return ahead(screen) == 1
  end, "the pane did not show ↑1 before the push")
  local function toggle()
    screen:exec([[
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      require('codediff.ui.explorer').toggle_visibility(p)
    ]])
  end
  toggle()
  h.wait(screen, function()
    return screen:exec([[
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      return not (p.winid and vim.api.nvim_win_is_valid(p.winid))
    ]])
  end, "the pane did not hide")
  h.git(dir, "push", "-q", "origin", "main")
  vim.wait(1500)
  toggle()
  h.wait(screen, function()
    return ahead(screen) == 0
  end, "the pane still shows ↑1 after the push made while it was hidden", 8000)
  screen:close()
end)

-- A commit and a push right after it (P on the repository row a moment after committing): the read
-- the commit started must not put back its ↑1 after the push.
for _, how in ipairs({ "outside", "P" }) do
  lib.test("the Git pane drops ↑1 after a commit and an immediate push (" .. how .. ")", function()
    local remote = h.tmpdir()
    h.git(remote, "init", "-q", "--bare", "-b", "main")
    local dir = h.repo({ ["a.txt"] = { "one" } })
    h.git(dir, "remote", "add", "origin", remote)
    h.git(dir, "push", "-q", "-u", "origin", "main")
    local screen = h.nvim(dir)
    screen:exec("require('codediff.config').options.scm.auto_fetch = false; vim.cmd('CodeDiff scm')")
    h.wait(screen, function()
      return ahead(screen) == 0
    end, "the pane did not open")
    for round = 1, 5 do
      h.write(dir .. "/a.txt", { "round " .. round })
      h.git(dir, "commit", "-q", "-am", "round " .. round)
      vim.wait(80 * round)
      if how == "outside" then
        h.git(dir, "push", "-q", "origin", "main")
      else
        screen:exec(
          "require('codediff.ui.explorer.actions').push(require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage()), ...)",
          { dir }
        )
        h.wait(screen, function()
          return vim.trim(vim.fn.system({ "git", "-C", dir, "rev-list", "--count", "@{u}..HEAD" })) == "0"
        end, "P did not push")
      end
      vim.wait(1500)
      lib.eq(0, ahead(screen), "round " .. round .. ": the pane still shows ↑ after the push")
    end
    screen:close()
  end)
end

-- The cause: a read that was published while the selection changed (the cursor is held on the
-- repository row after a commit) is remembered as "served", and the next read with the same event
-- skipped the panel. The push's refresh (and the watcher's refs change merged into it) is exactly
-- that event, so the ↑1 stayed. A request made after that read must always read again.
lib.test("a refresh requested after a served read still reads the pane", function()
  local top = h.tmpdir()
  local roots = {}
  for i = 1, 2 do
    local remote = h.tmpdir()
    h.git(remote, "init", "-q", "--bare", "-b", "main")
    local dir = top .. "/org/repo" .. i
    vim.fn.mkdir(dir, "p")
    h.git(dir, "init", "-q", "-b", "main")
    h.write(dir .. "/a.txt", { "one" })
    h.git(dir, "add", ".")
    h.git(dir, "commit", "-q", "-m", "base")
    h.git(dir, "remote", "add", "origin", remote)
    h.git(dir, "checkout", "-q", "-b", "feat/x")
    h.git(dir, "push", "-q", "-u", "origin", "feat/x")
    roots[#roots + 1] = dir
  end
  local dir = roots[2]
  h.write(dir .. "/a.txt", { "two" })
  h.git(dir, "commit", "-q", "-am", "second")
  local screen = h.nvim(top)
  screen:exec(
    [[
    require('codediff').setup({ scm = { only_listed = true, repositories = ..., auto_fetch = false } })
    vim.cmd('CodeDiff scm')
  ]],
    { roots }
  )
  local function count()
    return screen:exec([[
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      if not p or not p.tree then return -1 end
      for line = 1, vim.api.nvim_buf_line_count(p.bufnr) do
        local data = (p.tree:get_node(line) or {}).data or {}
        if data.type == 'repository' and data.name == 'repo2' then return data.ahead or 0 end
      end
      return -1
    ]])
  end
  h.wait(screen, function()
    return count() == 1
  end, "the pane did not show ↑1 before the push")
  h.wait(screen, function()
    return screen:exec([[
      local c = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage()).refresh
      return c and c.native and not c.running and not c.loading and next(c.pending) == nil
    ]])
  end, "the pane did not settle")
  local served = screen:exec(
    [[
    local root = ...
    local c = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage()).refresh
    -- the event P asks for after a push; the watcher's refs change of the same repository merges into it
    _G.push_event = { worktree = true, index = true, head = true, refs = true, roots = { [root] = true } }
    -- the state after a commit's read that was published while the cursor moved
    c.panel_served = require('codediff.ui.refresh.policy').normalize(vim.deepcopy(_G.push_event))
    return c.panel_served
  ]],
    { dir }
  )
  lib.ok(served, "no served state")
  -- the watcher's own report of the push arrives together with P's request, in the same run: stop the
  -- watcher and send both, so no later separate report can hide the skipped read
  screen:exec([[
    local c = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage()).refresh
    c:unwatch()
    -- and the periodic re-reads, which would correct it seconds later
    c.poll:stop()
    if c.reconcile_timer then c.reconcile_timer:stop() end
  ]])
  h.git(dir, "push", "-q", "origin", "feat/x")
  screen:exec(
    [[
    local root = ...
    local c = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage()).refresh
    c:request(_G.push_event)
    c:request({ type = 'refresh', refs = true, head = false, index = false, worktree = false, roots = { [root] = true } })
  ]],
    { dir }
  )
  h.wait(screen, function()
    return count() == 0
  end, "the pane kept ↑1: the refresh after the push skipped reading the pane", 5000)
  screen:close()
end)
