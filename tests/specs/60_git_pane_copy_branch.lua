-- Cmd+Shift+C in the Git pane copies the current branch of the project under the cursor (its row,
-- its branch line or one of its files), with a notification, like the copy in the Git graph.
local lib = require("lib")
local h = require("support")

local function pane(screen)
  screen:exec([[
    _G.copy_notes, _G.pbcopy = {}, {}
    -- never the real clipboard of the machine running the tests
    local system = vim.fn.system
    vim.fn.system = function(cmd, input)
      if type(cmd) == 'table' and cmd[1] == 'pbcopy' then
        table.insert(_G.pbcopy, input)
        return ''
      end
      return system(cmd, input)
    end
    vim.cmd('CodeDiff scm')
  ]])
end

-- Put the pane's cursor on the first row whose node matches `match` and press Cmd+Shift+C.
local function copy_on(screen, match)
  h.wait(screen, function()
    return screen:exec(
      [[
      local match = ...
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      if not p or not p.tree then return false end
      for line = 1, vim.api.nvim_buf_line_count(p.bufnr) do
        local node = p.tree:get_node(line)
        local data = node and node.data or {}
        if (match.type == nil or data.type == match.type) and (match.path == nil or data.path == match.path)
          and (match.name == nil or data.name == match.name) then
          vim.api.nvim_set_current_win(p.winid)
          vim.api.nvim_win_set_cursor(p.winid, { line, 0 })
          return true
        end
      end
      return false
    ]],
      { match }
    )
  end, "no row for " .. vim.inspect(match))
  -- wrapped right before the key: Snacks replaces vim.notify when its notifier first loads
  screen:exec([[
    _G.copy_notes, _G.pbcopy = {}, {}
    local notify = vim.notify
    vim.notify = function(message, level, opts)
      table.insert(_G.copy_notes, message)
      return notify(message, level, opts)
    end
    vim.fn.maparg('<D-S-c>', 'n', false, true).callback()
    vim.notify = notify
  ]])
  return screen:exec("return { notes = _G.copy_notes, pbcopy = _G.pbcopy, reg = vim.fn.getreg('\"') }")
end

lib.test("Cmd+Shift+C in the Git pane copies the project's branch", function()
  local dir = h.repo({ ["a.txt"] = { "one" } })
  h.git(dir, "checkout", "-q", "-b", "feat/copy-me")
  h.write(dir .. "/a.txt", { "two" })
  local screen = h.nvim(dir)
  pane(screen)
  local copied = copy_on(screen, { path = "a.txt" })
  lib.eq({ "Branch name copied: feat/copy-me" }, copied.notes)
  lib.eq("feat/copy-me", copied.reg)
  if vim.fn.has("mac") == 1 then
    lib.eq({ "feat/copy-me" }, copied.pbcopy)
  end
  screen:close()
end)

lib.test("Cmd+Shift+C in the Git pane copies the branch of the project under the cursor", function()
  -- like supernova: the parent ignores the packages folder, each package is its own repository
  local dir = h.repo({ ["a.txt"] = { "one" }, [".gitignore"] = { "packages/" } })
  local nested = dir .. "/packages/pkg"
  vim.fn.mkdir(nested, "p")
  h.git(nested, "init", "-q", "-b", "develop")
  h.write(nested .. "/b.txt", { "one" })
  h.git(nested, "add", ".")
  h.git(nested, "commit", "-q", "-m", "base")
  h.git(nested, "checkout", "-q", "-b", "feat/nested")
  h.write(nested .. "/b.txt", { "two" })
  h.write(dir .. "/a.txt", { "two" })
  local screen = h.nvim(dir)
  pane(screen)
  local rows
  h.wait(screen, function()
    rows = screen:exec([[
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      local found = {}
      if not p or not p.tree then return found end
      for line = 1, vim.api.nvim_buf_line_count(p.bufnr) do
        local data = (p.tree:get_node(line) or {}).data or {}
        if data.type == 'repository' and data.branch then found[#found + 1] = data.name .. '@' .. data.branch end
      end
      return found
    ]])
    return #rows >= 2
  end, "the pane did not list both projects")
  for _, row in ipairs(rows) do
    local name, branch = row:match("^(.-)@(.*)$")
    local copied = copy_on(screen, { type = "repository", name = name })
    lib.eq({ "Branch name copied: " .. branch }, copied.notes, "row " .. name)
  end
  local copied = copy_on(screen, { path = "b.txt" })
  lib.eq({ "Branch name copied: feat/nested" }, copied.notes, "a file of the nested project")
  screen:close()
end)

lib.test("Cmd+Shift+C in the Git pane on a detached project says it is not on a branch", function()
  local dir = h.repo({ ["a.txt"] = { "one" } })
  h.git(dir, "checkout", "-q", "--detach")
  h.write(dir .. "/a.txt", { "two" })
  local screen = h.nvim(dir)
  pane(screen)
  screen:exec("vim.fn.setreg('\"', 'before')")
  local copied = copy_on(screen, { path = "a.txt" })
  lib.eq(1, #copied.notes)
  lib.ok(copied.notes[1]:find("not on a branch", 1, true), copied.notes[1])
  lib.eq("before", copied.reg, "something was copied")
  lib.eq({}, copied.pbcopy)
  screen:close()
end)
