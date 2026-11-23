-- ggc in the Git pane (lua/core/git-branch-commit.lua): a branch name box, the commit message written from it below,
-- Enter creates the branch, stages everything and commits.
local lib = require("lib")
local h = require("support")

package.path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h") .. "/lua/?.lua;" .. package.path
local bc = require("core.git-branch-commit")

lib.test("git branch commit: the message is written from the branch name, for every character typed", function()
  lib.eq("feat(core-334): some text", bc.message_for("feat/core-334-some text"))
  lib.eq("feat(core-334): some text", bc.message_for("feat/core-334-some-text"))
  lib.eq("fix(PAY-12): retry on timeout", bc.message_for("fix/PAY-12-retry_on_timeout"))
  lib.eq("feat(core-334): v2 fix", bc.message_for("feat/core-334-v2-fix"), "a number in the text stays text")
  -- while typing: the format at every step
  local steps = {
    { "f", "f" },
    { "feat", "feat" },
    { "feat/", "feat()" },
    { "feat/co", "feat(co)" },
    { "feat/core-", "feat(core-)" },
    { "feat/core-33", "feat(core-33)" },
    { "feat/core-334", "feat(core-334)" },
    { "feat/core-334-", "feat(core-334): " },
    { "feat/core-334-so", "feat(core-334): so" },
    { "feat/core-334-some-", "feat(core-334): some " },
  }
  for _, step in ipairs(steps) do
    lib.eq(step[2], bc.message_for(step[1]), "after typing " .. step[1])
  end
  lib.eq("", bc.message_for(""))
  lib.eq("feat/core-334-some-text", bc.branch_name(" feat/core-334-some text "))
end)

lib.test("git branch commit: the branch box is cleaned like C's new branch while typing", function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local screen = h.nvim(dir)
  local function clean(text)
    return screen:exec("return require('core.git-branch-commit').clean_branch(...)", { text })
  end
  lib.eq("feat/core-334-some-text", clean("feat/core-334-some text"))
  lib.eq("feat/core-1-a-b", clean("feat/core-1-a  ~b"))
  lib.eq("feat/x", clean("feat//x"))
  lib.eq("feat/core-1", screen:exec("return require('core.git-branch-commit').branch_name('feat/core-1-')"))
  screen:close()
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
  -- Selecting a.txt loads its diff later, and that load moves through the diff windows. Landing after ggc (a busy
  -- machine) it had a "Press ENTER" prompt eat the typed keys in a read-only diff window: E21 for every key.
  -- So the diff is loaded and the Git pane has the cursor again before a test types anything.
  h.wait(screen, function()
    return screen:exec([[
      local lifecycle = require('codediff.ui.lifecycle')
      local tab = vim.api.nvim_get_current_tabpage()
      local s, p = lifecycle.get_session(tab), lifecycle.get_panel_view(tab)
      if not s or not s.stored_diff_result or #(s.stored_diff_result.changes or {}) == 0 then return false end
      if s.refresh and (s.refresh.loading or s.refresh.running) then return false end
      if not (s.modified_bufnr and vim.api.nvim_buf_get_name(s.modified_bufnr):find('a.txt', 1, true)) then return false end
      vim.api.nvim_set_current_win(p.winid)
      return true
    ]])
  end, "the diff of a.txt did not load")
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
      and h.find_on_screen(screen, "Enter create branch, stage all, commit") ~= nil
  end, "the boxes, their placeholders and the keys line are not on the screen")
  lib.eq(1, screen:exec([[
    local n = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.wo[win].winhighlight:find("ModalBackdrop", 1, true) then n = n + 1 end
    end
    return n
  ]]), "the screen behind the boxes is dimmed")
  lib.eq({ {}, {} }, screen:exec([[
    local s = require("core.git-branch-commit").state()
    return { vim.api.nvim_buf_get_extmarks(s.branch_buf, -1, 0, -1, {}), vim.api.nvim_buf_get_extmarks(s.message_buf, -1, 0, -1, {}) }
  ]]), "the boxes are empty: no placeholder text")
  -- one key at a time, like a person types: the message is right after every one
  local typed = ""
  for _, key in ipairs(vim.split("feat/core-334-some text", "")) do
    screen:input(key == " " and "<Space>" or key)
    typed = typed .. key
    local want = bc.message_for(typed)
    h.wait(screen, function()
      return screen:exec([[
        local s = require("core.git-branch-commit").state()
        return vim.api.nvim_buf_get_lines(s.message_buf, 0, -1, false)[1]
      ]]) == want
    end, "the message did not follow after typing " .. typed)
  end
  h.wait(screen, function()
    return h.find_on_screen(screen, "feat(core-334): some text") ~= nil
  end, "the commit message is not on the screen")
  lib.eq("feat/core-334-some-text", screen:exec([[
    return vim.api.nvim_buf_get_lines(require("core.git-branch-commit").state().branch_buf, 0, -1, false)[1]
  ]]), "the space in the branch box became a dash, like C's new branch")
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
  -- This test failed once under a full parallel run: everything typed landed in a read-only buffer (E21). Until
  -- the cause is known, every focus / mode / buffer change after ggc is recorded and printed with a failure.
  screen:exec([[
    _G.focus_log = {}
    vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter", "ModeChanged" }, { callback = function(ev)
      local where = vim.split(debug.traceback("", 2), "\n")
      table.insert(_G.focus_log, ("%s win=%d ft=%s modifiable=%s mode=%s | %s"):format(ev.event, vim.api.nvim_get_current_win(),
        vim.bo.filetype, tostring(vim.bo.modifiable), vim.fn.mode(), vim.trim(where[3] or "") .. " " .. vim.trim(where[4] or "")))
    end })
  ]])
  local function wait_logged(predicate, message)
    local ok, err = pcall(h.wait, screen, predicate, message)
    if not ok then
      error(tostring(err) .. "\n--- focus log ---\n" .. table.concat(screen:exec("return _G.focus_log"), "\n"), 0)
    end
  end
  screen:input("ggc")
  -- typing starts only once the branch box has the cursor in insert mode (ggc's startinsert has run)
  wait_logged(function()
    return screen:exec([[
      local s = require("core.git-branch-commit").state()
      return s ~= nil and vim.api.nvim_get_current_win() == s.branch_win and vim.fn.mode() == "i"
    ]])
  end, "ggc did not open the branch box in insert mode")
  screen:input("fix/pay-9-x<Tab><C-u>fix(pay-9): my own words<Tab>yz")
  wait_logged(function()
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
