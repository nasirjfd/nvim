local lib = require("lib")
local h = require("support")

local function pane(dir)
  local screen = h.nvim(dir)
  screen:exec([[
    _G.opened_urls, _G.browser_notes = {}, {}
    vim.ui.open = function(url) table.insert(_G.opened_urls, url) end
    vim.notify = function(message) table.insert(_G.browser_notes, message) end
    vim.cmd('CodeDiff scm')
  ]])
  h.wait(screen, function()
    return screen:exec([[
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      if not (p and p.tree and vim.bo.filetype == 'codediff-explorer'
        and vim.fn.maparg('ggm', 'n', false, true).buffer == 1) then return false end
      for row = 1, vim.api.nvim_buf_line_count(0) do
        local node = p.tree:get_node(row)
        if node and node.data and node.data.git_root then
          vim.api.nvim_win_set_cursor(0, { row, 0 })
          return true
        end
      end
      return false
    ]])
  end, "Git pane did not open with the ggm mapping")
  return screen
end

for _, remote in ipairs({
  "https://git.digikala.com/supernova/supernova-digiexpress.git",
  "git@git.digikala.com:supernova/supernova-digiexpress.git",
  "ssh://git@git.digikala.com:2222/supernova/supernova-digiexpress.git",
}) do
  lib.test("ggm opens the merge-request list for " .. remote, function()
    local dir = h.repo({ ["a.txt"] = { "one" } })
    h.git(dir, "remote", "add", "origin", remote)
    local screen = pane(dir)
    screen:input("ggm")
    h.wait(screen, function()
      return screen:exec("return #_G.opened_urls") == 1
    end, "ggm did not open a browser URL")
    lib.eq(
      "https://git.digikala.com/supernova/supernova-digiexpress/-/merge_requests",
      screen:exec("return _G.opened_urls[1]")
    )
    screen:close()
  end)
end

lib.test("ggm follows the selected repository instead of the workspace directory", function()
  local workspace = h.tmpdir()
  for _, name in ipairs({ "first", "second" }) do
    local repo = workspace .. "/" .. name
    h.write(repo .. "/a.txt", { "one" })
    h.git(repo, "init", "-q", "-b", "main")
    h.git(repo, "add", "a.txt")
    h.git(repo, "commit", "-q", "-m", "base")
    h.git(repo, "remote", "add", "origin", "git@git.example.com:group/" .. name .. ".git")
  end
  local screen = pane(workspace)
  for _, name in ipairs({ "second", "first" }) do
    screen:exec(
      [[
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      for row = 1, vim.api.nvim_buf_line_count(0) do
        local node = p.tree:get_node(row)
        if node and node.data and node.data.git_root == (...) then
          vim.api.nvim_win_set_cursor(0, { row, 0 })
          return
        end
      end
      error('repository row not found')
    ]],
      { workspace .. "/" .. name }
    )
    screen:input("ggm")
    h.wait(screen, function()
      return screen:exec("return _G.opened_urls[#_G.opened_urls]")
        == "https://git.example.com/group/" .. name .. "/-/merge_requests"
    end, "ggm opened the wrong repository")
  end
  screen:close()
end)

lib.test("ggm uses the upstream remote like ggr and handles missing remotes", function()
  local dir = h.repo({ ["a.txt"] = { "one" } })
  h.git(dir, "remote", "add", "origin", "https://git.example.com/fork/repo.git")
  h.git(dir, "remote", "add", "upstream", "https://git.example.com/group/repo.git")
  h.git(dir, "update-ref", "refs/remotes/upstream/main", "HEAD")
  h.git(dir, "branch", "--set-upstream-to=upstream/main", "main")
  local screen = pane(dir)
  screen:input("ggm")
  h.wait(screen, function()
    return screen:exec("return #_G.opened_urls") == 1
  end, "browser did not open")
  lib.eq(
    "https://git.example.com/group/repo/-/merge_requests",
    screen:exec("return _G.opened_urls[1]")
  )
  h.git(dir, "remote", "remove", "origin")
  h.git(dir, "remote", "remove", "upstream")
  screen:exec("require('core.git-merge-requests').open()")
  lib.eq(1, screen:exec("return #_G.opened_urls"), "missing remote opened a bogus page")
  lib.eq(
    "This repository has no Git remote",
    screen:exec("return _G.browser_notes[#_G.browser_notes]")
  )
  screen:close()
end)
