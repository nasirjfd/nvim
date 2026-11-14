-- Option+Cmd+Z reverts the hunk under the cursor in a diff tab, and only that hunk.
local lib = require("lib")
local h = require("support")

local function editor(dir)
  local screen = h.nvim(dir)
  screen:exec([[
    _G.hunk_prompts, _G.hunk_notifications = {}, {}
    require('core.revert-confirm').ask = function(callback)
      table.insert(_G.hunk_prompts, 'Revert staged hunk')
      callback(true)
    end
    vim.notify = function(message) table.insert(_G.hunk_notifications, message) end
  ]])
  return screen
end

for _, answer in ipairs({ { "y", true }, { "<CR>", true }, { "n", false }, { "<Esc>", false } }) do
  lib.test("staged hunk confirmation responds to " .. answer[1], function()
    local dir = h.repo({ ["a.txt"] = { "one", "two", "three" } })
    h.write(dir .. "/a.txt", { "one", "STAGED", "three" })
    h.git(dir, "add", "a.txt")
    local before = h.git(dir, "diff", "--cached")
    local screen = h.nvim(dir)
    screen:exec("vim.cmd('edit a.txt')")
    h.wait(screen, function()
      return screen:exec("return require('gitsigns').get_hunks() ~= nil")
    end, "Git hunks did not attach")
    local approve = answer[2]
    screen:exec("vim.api.nvim_win_set_cursor(0, { 2, 0 }); require('core.revert-hunk').reset()")
    h.wait(screen, function()
      return screen:exec("return vim.bo.filetype == 'revert_confirm'")
    end, "confirmation popup did not open")
    lib.eq(
      "STAGED",
      screen:exec("return vim.api.nvim_buf_get_lines(vim.fn.bufnr('a.txt'), 1, 2, false)[1]")
    )
    lib.eq(before, h.git(dir, "diff", "--cached"), "index changed before confirmation")
    lib.ok(
      screen:exec([[
        return not vim.bo.modifiable and vim.fn.mode() == 'n'
          and vim.api.nvim_buf_get_lines(0,4,5,false)[1]:find('%[ Yes %].*%[ No %]') ~= nil
          and #Snacks.picker.get({source='select'}) == 0
      ]]),
      "confirmation must have horizontal buttons and no text input"
    )
    screen:exec("_G.confirm_text = vim.api.nvim_buf_get_lines(0,0,-1,false)")
    screen:input("ipasted code")
    lib.eq(
      screen:exec("return _G.confirm_text"),
      screen:exec("return vim.api.nvim_buf_get_lines(0,0,-1,false)"),
      "typing edited the dialog"
    )
    lib.eq("n", screen:exec("return vim.fn.mode()"), "dialog entered text-entry mode")
    screen:input("<Esc>")
    h.wait(screen, function()
      return screen:exec(
        "return vim.b.reverting_staged_hunk == nil and vim.bo.filetype ~= 'revert_confirm'"
      )
    end, "Escape did not dismiss the read-only dialog")
    lib.eq(before, h.git(dir, "diff", "--cached"), "typing changed the index")
    screen:exec("require('core.revert-hunk').reset()")
    h.wait(screen, function()
      return screen:exec("return vim.bo.filetype == 'revert_confirm'")
    end, "confirmation did not reopen")
    lib.eq(
      screen:exec("return _G.confirm_text"),
      screen:exec("return vim.api.nvim_buf_get_lines(0,0,-1,false)")
    )
    screen:input(answer[1])
    h.wait(screen, function()
      return screen:exec(
        "return vim.bo.filetype ~= 'revert_confirm' and vim.b.reverting_staged_hunk == nil"
      )
    end, "confirmation did not finish")
    if not approve then
      lib.eq(before, h.git(dir, "diff", "--cached"), "Cancel changed the index")
      lib.eq("STAGED", screen:exec("return vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]"))
    else
      h.wait(screen, function()
        return screen:exec("return vim.api.nvim_buf_get_lines(0, 1, 2, false)[1] == 'two'")
      end, "approved hunk was not reverted")
      lib.eq("", h.git(dir, "diff", "--cached"))
    end
    screen:close()
  end)
end

for _, kind in ipairs({ "addition", "deletion" }) do
  lib.test("cmd+alt+z reverts a staged " .. kind, function()
    local base = {}
    for i = 1, 20 do
      base[i] = "line " .. i
    end
    local dir = h.repo({ ["a.txt"] = base })
    local changed = vim.deepcopy(base)
    if kind == "addition" then
      table.insert(changed, 5, "NEW LINE")
    else
      table.remove(changed, 5)
    end
    h.write(dir .. "/a.txt", changed)
    h.git(dir, "add", "a.txt")
    local screen = editor(dir)
    screen:exec("vim.cmd('edit a.txt')")
    h.wait(screen, function()
      return screen:exec("return require('gitsigns').get_hunks() ~= nil")
    end, "Git hunks did not attach")
    screen:exec("vim.api.nvim_win_set_cursor(0, { ..., 0 }); require('core.revert-hunk').reset()", {
      kind == "addition" and 5 or 4,
    })
    h.wait(screen, function()
      return vim.deep_equal(base, screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
    end, "staged " .. kind .. " was not reverted")
    lib.eq("", h.git(dir, "diff", "--cached"), "staged hunk remained in the index")
    screen:close()
  end)
end

lib.test("cmd+alt+z finds a staged hunk below an unstaged insertion", function()
  local base = {}
  for i = 1, 45 do
    base[i] = "line " .. i
  end
  local dir = h.repo({ ["a.txt"] = base })
  local changed = vim.deepcopy(base)
  changed[35] = "STAGED 35"
  h.write(dir .. "/a.txt", changed)
  h.git(dir, "add", "a.txt")
  table.insert(changed, 1, "UNSTAGED NEW LINE")
  h.write(dir .. "/a.txt", changed)
  local screen = editor(dir)
  screen:exec("vim.cmd('edit a.txt')")
  h.wait(screen, function()
    return screen:exec("local h = require('gitsigns').get_hunks(); return h and #h == 1")
  end, "Git hunks did not attach")
  screen:exec("vim.api.nvim_win_set_cursor(0, { 36, 0 })")
  vim.wait(150)
  screen:input("<D-M-z>")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_buf_get_lines(0, 35, 36, false)[1] == 'line 35'")
  end, function()
    return "shifted staged hunk was not reverted: "
      .. vim.inspect(screen:exec([[
      return { cursor=vim.api.nvim_win_get_cursor(0), pending=vim.b.reverting_staged_hunk,
        hunks=require('gitsigns').get_hunks(), lines=vim.api.nvim_buf_get_lines(0,33,38,false),
        messages=vim.api.nvim_exec2('messages',{output=true}).output }
    ]]))
  end)
  lib.eq("UNSTAGED NEW LINE", screen:exec("return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]"))
  lib.eq(table.concat(base, "\n") .. "\n", h.git(dir, "show", ":a.txt"))
  screen:close()
end)

lib.test("cmd+alt+z on a clean line does not stage another hunk", function()
  local dir = h.repo({ ["a.txt"] = { "one", "two", "three", "four", "five" } })
  h.write(dir .. "/a.txt", { "one", "two", "three", "four", "UNSTAGED" })
  local screen = editor(dir)
  screen:exec("vim.cmd('edit a.txt')")
  h.wait(screen, function()
    return screen:exec("local h = require('gitsigns').get_hunks(); return h and #h == 1")
  end, "Git hunks did not attach")
  screen:exec("vim.api.nvim_win_set_cursor(0, { 1, 0 }); require('core.revert-hunk').reset()")
  vim.wait(150)
  lib.eq("", h.git(dir, "diff", "--cached"), "unrelated hunk was staged")
  lib.eq("UNSTAGED", screen:exec("return vim.api.nvim_buf_get_lines(0, 4, 5, false)[1]"))
  screen:close()
end)

lib.test(
  "cmd+alt+z reverts a staged hunk without touching other staged or unstaged hunks",
  function()
    local base = {}
    for i = 1, 45 do
      base[i] = "line " .. i
    end
    local dir = h.repo({ ["a.txt"] = base })
    local changed = vim.deepcopy(base)
    changed[5], changed[35] = "STAGED 5", "STAGED 35"
    h.write(dir .. "/a.txt", changed)
    h.git(dir, "add", "a.txt")
    changed[20] = "UNSTAGED 20"
    h.write(dir .. "/a.txt", changed)
    local screen = editor(dir)
    screen:exec("vim.cmd('edit a.txt')")
    h.wait(screen, function()
      return screen:exec([[
      local gs = require('gitsigns')
      return gs.get_hunks() and #gs.get_hunks() == 1 and vim.b.gitsigns_head ~= nil
    ]])
    end, "Git hunks did not attach")
    screen:exec([[
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    vim.fn.maparg('<D-M-z>', 'n', false, true).callback()
  ]])
    h.wait(screen, function()
      return screen:exec("return vim.api.nvim_buf_get_lines(0, 4, 5, false)[1] == 'line 5'")
    end, "staged hunk was not reverted")
    lib.eq("UNSTAGED 20", screen:exec("return vim.api.nvim_buf_get_lines(0, 19, 20, false)[1]"))
    lib.eq("STAGED 35", screen:exec("return vim.api.nvim_buf_get_lines(0, 34, 35, false)[1]"))
    local index = vim.split(h.git(dir, "show", ":a.txt"), "\n")
    lib.eq("line 5", index[5], "target staged hunk was not removed from the index")
    lib.eq("line 20", index[20], "unrelated unstaged hunk was staged")
    lib.eq("STAGED 35", index[35], "unrelated staged hunk was removed")
    lib.eq(1, screen:exec("return #_G.hunk_prompts"), "staged revert did not ask for confirmation")
    lib.eq(
      "Reverted staged hunk",
      screen:exec("return _G.hunk_notifications[#_G.hunk_notifications]")
    )
    screen:input("u")
    h.wait(screen, function()
      return screen:exec("return vim.api.nvim_buf_get_lines(0, 4, 5, false)[1] == 'STAGED 5'")
    end, "revert was not undoable")
    screen:close()
  end
)

lib.test("cmd+alt+z reverts only the hunk under the cursor in a working-tree diff", function()
  local base = {}
  for i = 1, 40 do
    base[i] = "line " .. i
  end
  local dir = h.repo({ ["a.txt"] = base })
  local changed = vim.deepcopy(base)
  changed[5], changed[30] = "CHANGED 5", "CHANGED 30"
  h.write(dir .. "/a.txt", changed)

  local screen = editor(dir)
  screen:exec("vim.cmd('edit a.txt'); vim.cmd('CodeDiff')")
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      return s ~= nil and s.stored_diff_result ~= nil and s.stored_diff_result.changes ~= nil and #s.stored_diff_result.changes == 2
    ]])
  end, "the diff never opened")
  screen:exec([[
    local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
    vim.api.nvim_set_current_win(s.modified_win)
    vim.api.nvim_win_set_cursor(s.modified_win, { 5, 0 })
    vim.fn.maparg('<D-M-z>', 'n', false, true).callback()
  ]])
  h.wait(screen, function()
    return h.read(dir .. "/a.txt")[5] == "line 5"
  end, "the hunk under the cursor was not reverted")
  lib.eq("CHANGED 30", h.read(dir .. "/a.txt")[30], "the other hunk must stay")
  screen:close()
end)
