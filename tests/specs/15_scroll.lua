local lib = require("lib")
local h = require("support")

local function editor()
  local screen = h.nvim(h.tmpdir())
  screen:exec([[
    vim.cmd('enew')
    local lines = {}
    for i = 1, 1000 do lines[i] = ('line %d'):format(i) end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.cmd('normal! 200Gzt')
  ]])
  vim.wait(150)
  return screen
end

lib.test("scroll wheel moves immediately and has no animation tail", function()
  local screen = editor()
  local before = screen:exec("return vim.fn.line('w0')")
  screen:request("nvim_input_mouse", { "wheel", "down", "", 0, 10, 30 })
  h.wait(screen, function()
    return screen:exec("return vim.fn.line('w0')") == before + 1
  end, "wheel did not move exactly one line")
  vim.wait(150)
  assert(screen:exec("return vim.fn.line('w0')") == before + 1, "wheel drifted after input stopped")
  screen:request("nvim_input_mouse", { "wheel", "up", "", 0, 10, 30 })
  h.wait(screen, function()
    return screen:exec("return vim.fn.line('w0')") == before
  end, "wheel reversal did not respond immediately")
  screen:close()
end)

lib.test("scroll wheel does not finish an old keyboard animation", function()
  local screen = editor()
  screen:exec([[
    _G.scroll_finished = false
    _G.scroll_test_anim = Snacks.animate.add(0, 100, function(_, ctx)
      if ctx.done then _G.scroll_finished = true end
    end, { id = 'scroll_interrupt_test', duration = 10000 })
  ]])
  screen:request("nvim_input_mouse", { "wheel", "down", "", 0, 10, 30 })
  vim.wait(50)
  assert(not screen:exec("return _G.scroll_finished"), "wheel snapped to the old animation's destination")
  screen:exec("_G.scroll_test_anim:stop()")
  screen:close()
end)

lib.test("scroll wheel cancels a real glide without drifting afterward", function()
  local screen = editor()
  screen:exec([[
    vim.cmd('normal! 600Gzt')
    Snacks.scroll.check(vim.api.nvim_get_current_win())
  ]])
  screen:request("nvim_input_mouse", { "wheel", "down", "", 0, 10, 30 })
  vim.wait(30)
  local stopped = screen:exec("return vim.fn.line('w0')")
  assert(stopped < 600, "wheel finished the keyboard glide instead of cancelling it")
  vim.wait(150)
  assert(screen:exec("return vim.fn.line('w0')") == stopped, "old glide kept moving after wheel input")
  screen:exec("assert(vim.wo.virtualedit == '' and vim.wo.scrolloff == vim.o.scrolloff)")
  screen:close()
end)

lib.test("scroll keyboard input still finishes an interrupted animation", function()
  local screen = editor()
  screen:exec([[
    _G.scroll_finished = false
    Snacks.animate.add(0, 100, function(_, ctx)
      if ctx.done then _G.scroll_finished = true end
    end, { id = 'scroll_interrupt_test', duration = 10000 })
  ]])
  screen:request("nvim_input", { "j" })
  h.wait(screen, function()
    return screen:exec("return _G.scroll_finished")
  end, "keyboard input did not finish the old animation")
  screen:close()
end)
