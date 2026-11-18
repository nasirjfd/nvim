local lib = require("lib")
local h = require("support")

lib.test("closing a picker inside the input debounce leaves no error behind", function()
  local dir = h.repo({ ["a.txt"] = { "a" }, ["b.txt"] = { "b" } })
  local screen = h.nvim(dir)
  screen:exec("Snacks.picker.files()")
  h.wait(screen, function()
    return screen:exec("local p = Snacks.picker.get({ source = 'files' })[1]; return p and not p.finder:running() and p:count() == 2")
  end, "the file picker did not list the files")
  screen:exec([[
    local p = Snacks.picker.get({ source = 'files' })[1]
    _G.late_input = p.input
    p:close()
  ]])
  vim.wait(300) -- the picker's windows and input are closed by now
  -- what Snacks' debounced input handler does when it is late (Enter right after typing): it finds
  -- through the input's picker, which is nil once the input is closed
  screen:exec([[
    _G.late_find_error = select(2, pcall(function()
      _G.late_input.picker:find({ refresh = false })
    end))
  ]])
  local late = screen:exec("return _G.late_find_error")
  lib.ok(late == nil or late == vim.NIL, "a late input find raised an error: " .. tostring(late))
  screen:close()
end)
