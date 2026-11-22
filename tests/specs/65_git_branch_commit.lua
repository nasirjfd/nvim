-- ggc in the Git pane (lua/core/git-branch-commit.lua): a branch name box, the commit message written from it below,
-- Enter creates the branch, stages everything and commits.
local lib = require("lib")
local h = require("support")

package.path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h") .. "/lua/?.lua;" .. package.path
local bc = require("core.git-branch-commit")

lib.test("git branch commit: the message is written from the branch name", function()
  lib.eq("feat(core-334): some text", bc.message_for("feat/core-334-some text"))
  lib.eq("feat(core-334): some text", bc.message_for("feat/core-334-some-text"))
  lib.eq("fix(PAY-12): retry on timeout", bc.message_for("fix/PAY-12-retry_on_timeout"))
  lib.eq("feat(core-334): ", bc.message_for("feat/core-334"), "while typing")
  lib.eq("chore: bump deps", bc.message_for("chore/bump-deps"), "no ticket: no scope")
  lib.eq("", bc.message_for("feat"), "no type yet")
  lib.eq("feat/core-334-some-text", bc.branch_name(" feat/core-334-some text "))
end)

local function git_pane(dir)
  local screen = h.nvim(dir)
  screen:exec([[
    _G.notes = {}
    vim.notify = function(msg) table.insert(_G.notes, msg) end
    vim.cmd('CodeDiff scm')
  ]])
  h.wait(screen, function()
    return screen:exec([[
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      if not p or not p.tree then return false end
      for line = 1, vim.api.nvim_buf_line_count(p.bufnr) do
        local node = p.tree:get_node(line)
        if node and node.data and node.data.path == 'a.txt' then
          vim.api.nvim_set_current_win(p.winid)
          vim.api.nvim_win_set_cursor(p.winid, { line, 0 })
          return true
        end
      end
      return false
    ]])
  end, "the changed file did not show in the Git pane")
  return screen
end

lib.test("git branch commit: ggc shows both boxes with placeholders, the message follows, Enter branches and commits", function()
  local dir = h.repo({ ["a.txt"] = { "before" } })
  h.write(dir .. "/a.txt", { "after" })
  h.write(dir .. "/new.txt", { "untracked" })
  local screen = git_pane(dir)
  screen:input("ggc")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype") == "git_branch_commit" and screen:exec("return vim.fn.mode()") == "i"
  end, "ggc did not open the branch box in insert mode")
  h.wait(screen, function()
    return h.find_on_screen(screen, "New branch") ~= nil
      and h.find_on_screen(screen, "Commit message") ~= nil
      and h.find_on_screen(screen, "feat/core-334-short-description") ~= nil
      and h.find_on_screen(screen, "feat(core-334): short description") ~= nil
      and h.find_on_screen(screen, "Enter create branch, stage all, commit") ~= nil
  end, "the boxes, their placeholders and the keys line are not on the screen")
  lib.eq(1, screen:exec([[
    local n = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.wo[win].winhighlight:find("ModalBackdrop", 1, true) then n = n + 1 end
    end
    return n
  ]]), "the screen behind the boxes is dimmed")
  screen:input("feat/core-334-some text")
  h.wait(screen, function()
    return h.find_on_screen(screen, "feat(core-334): some text") ~= nil
  end, "the commit message did not follow the branch name")
  lib.ok(h.find_on_screen(screen, "feat/core-334-short-description") == nil, "the placeholder is gone once something is typed")
  screen:input("<CR>")
  h.wait(screen, function()
    local log = vim.fn.system({ "git", "-C", dir, "log", "-1", "--format=%s" })
    return vim.trim(log) == "feat(core-334): some text"
  end, "the commit was not made")
  lib.eq("feat/core-334-some-text", vim.trim(vim.fn.system({ "git", "-C", dir, "branch", "--show-current" })))
  lib.eq("", vim.trim(vim.fn.system({ "git", "-C", dir, "status", "--porcelain" })), "every change (also untracked) is committed")
  lib.eq(nil, screen:exec("return require('core.git-branch-commit').state()"), "the boxes are closed")
  h.wait(screen, function()
    return screen:exec([[
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.wo[win].winhighlight:find("ModalBackdrop", 1, true) then return false end
      end
      return true
    ]])
  end, "the backdrop must go with the boxes")
  screen:close()
end)

lib.test("git branch commit: a message changed by hand stays; Esc cancels and nothing happens", function()
  local dir = h.repo({ ["a.txt"] = { "before" } })
  h.write(dir .. "/a.txt", { "after" })
  local screen = git_pane(dir)
  screen:input("ggc")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype") == "git_branch_commit"
  end, "ggc did not open")
  screen:input("fix/pay-9-x<Tab><C-u>fix(pay-9): my own words<Tab>yz")
  h.wait(screen, function()
    return h.find_on_screen(screen, "fix/pay-9-xyz") ~= nil
  end, "typing in the branch box again")
  vim.wait(150) -- nothing else happens: the message must not be rewritten from the branch
  lib.ok(h.find_on_screen(screen, "fix(pay-9): my own words") ~= nil, "the message written by hand was replaced")
  screen:input("<Esc><Esc>")
  h.wait(screen, function()
    return screen:exec("return require('core.git-branch-commit').state()") == nil
  end, "Esc did not close the boxes")
  lib.eq("main", vim.trim(vim.fn.system({ "git", "-C", dir, "branch", "--show-current" })):gsub("master", "main"), "no branch was made")
  screen:close()
end)

lib.test("git branch commit: the Git pane's ? page lists ggc and ggm", function()
  local dir = h.repo({ ["a.txt"] = { "before" } })
  h.write(dir .. "/a.txt", { "after" })
  local screen = git_pane(dir)
  local rows = screen:exec([[
    local out = {}
    for _, row in ipairs(require("codediff.ui.welcome").git_shortcuts() or {}) do out[#out + 1] = row.key .. "=" .. row.desc end
    return out
  ]])
  lib.ok(vim.tbl_contains(rows, "ggc=New branch, stage all, commit"), "ggc missing: " .. vim.inspect(rows))
  lib.ok(vim.tbl_contains(rows, "ggm=Open Merge Requests in Browser"), "ggm missing: " .. vim.inspect(rows))
  screen:input("?")
  h.wait(screen, function()
    return h.find_on_screen(screen, "New branch, stage all, commit") ~= nil
  end, "? in the Git pane does not show ggc")
  screen:close()
end)
