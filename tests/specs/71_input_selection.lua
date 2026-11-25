local lib = require("lib")
local h = require("support")

local function prompt()
  local screen = h.nvim(h.tmpdir())
  screen:exec([[
    vim.ui.input({ prompt = 'New Name', default = 'hello world' }, function(value)
      _G.selection_answer = value
    end)
  ]])
  h.wait(screen, function()
    return screen:exec(
      "return vim.bo.filetype == 'snacks_input' and vim.fn.mode() == 'i' and vim.b.mac_input_navigation"
    )
  end, "rename input did not open")
  return screen
end

lib.test(
  "Shift arrows select text in rename inputs and typing replaces only the selection",
  function()
    local screen = prompt()
    screen:input("<End><S-Left><S-Left><S-Left><S-Left><S-Left>")
    h.wait(screen, function()
      return screen:exec([[
      local marks = vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace('input-text-selection'), 0, -1, { details = true })
      return #marks == 1 and marks[1][3] == 6 and marks[1][4].end_col == 11
    ]])
    end, "Shift+Left did not visibly select world")
    screen:input("name<CR>")
    h.wait(screen, function()
      return screen:exec("return _G.selection_answer == 'hello name'")
    end, "typing did not replace the selected text")
    screen:close()
  end
)

lib.test("Shift selection can shrink, collapse with arrows, and delete Unicode text", function()
  local screen = prompt()
  screen:input("<Home><S-Right><S-Right><S-Left><BS>")
  h.wait(screen, function()
    return screen:exec(
      "return vim.api.nvim_get_current_line() == 'ello world' and vim.fn.mode() == 'i'"
    )
  end, "reversing Shift selection or Backspace failed")
  screen:input("<S-Right><S-Right><Right>X")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_get_current_line() == 'elXlo world'")
  end, "plain Right did not collapse selection to its right edge")
  screen:exec("vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'aé界b' })")
  screen:input("<End><Left><S-Left><S-Left><Del><CR>")
  h.wait(screen, function()
    return screen:exec("return _G.selection_answer == 'ab'")
  end, "selection split a Unicode character or Delete failed")
  screen:close()
end)

lib.test("Shift line selection supports paste without changing editor options", function()
  local screen = prompt()
  local options = screen:exec("return { vim.o.keymodel, vim.o.selectmode, vim.o.selection }")
  screen:input("<Home><S-End>")
  screen:exec("vim.paste({ 'replacement' }, -1)")
  screen:input("<CR>")
  h.wait(screen, function()
    return screen:exec("return _G.selection_answer == 'replacement'")
  end, "pasting did not replace the selection")
  lib.eq(options, screen:exec("return { vim.o.keymodel, vim.o.selectmode, vim.o.selection }"))
  screen:close()
end)

lib.test("Shift word and Cmd line selection support copy, cut, and selection boundaries", function()
  local screen = prompt()
  screen:exec([[
    _G.selection_clipboard = {}
    vim.fn.setreg = function(reg, text) _G.selection_clipboard = { reg, text } end
  ]])
  screen:input("<End><C-S-Left><D-c>")
  h.wait(screen, function()
    return screen:exec("return _G.selection_clipboard[2] == 'world'")
  end, "Shift+Option+Left or copying the selected word failed")
  screen:input("<D-x>")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_get_current_line() == 'hello '")
  end, "cut did not remove only the selection")
  screen:input("<D-S-Left>X<Home><S-Left><S-Left><S-Right>Y<End><S-Right><CR>")
  h.wait(screen, function()
    return screen:exec("return _G.selection_answer == 'Y'")
  end, "Cmd+Shift selection or repeated selection at a field boundary failed")
  screen:close()
end)

lib.test("custom branch and commit text boxes support Shift selection too", function()
  local screen = h.nvim(h.repo({ ["a.txt"] = { "one" } }))
  screen:exec("require('core.git-branch-commit').open()")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'git_branch_commit' and vim.fn.mode() == 'i'")
  end, "branch dialog did not open")
  screen:input("feat/task-1-old<S-Left><S-Left><S-Left>new")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_get_current_line() == 'feat/task-1-new'")
  end, "Shift selection did not replace the branch suffix")
  screen:input("<Tab><Home><S-End>custom message")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_get_current_line() == 'custom message'")
  end, "Shift selection did not replace the generated commit message")
  screen:input("<C-c>")
  h.wait(screen, function()
    return screen:exec("return require('core.git-branch-commit').state() == nil")
  end, "Ctrl+C did not cancel the custom dialog")
  lib.ok(
    screen:exec("return vim.fn.maparg('<S-Left>', 'i') == ''"),
    "selection maps leaked into the editor"
  )
  screen:close()
end)
