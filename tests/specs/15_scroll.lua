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

lib.test("scroll keyboard resumes at the original editing position after wheeling offscreen", function()
  local screen = editor()
  for _ = 1, 35 do
    screen:request("nvim_input_mouse", { "wheel", "down", "", 0, 10, 30 })
  end
  vim.wait(150)
  screen:request("nvim_input", { "j" })
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_win_get_cursor(0)[1]") == 201
  end, "wheel moved the editing position")
  screen:close()
end)

lib.test("scroll Ctrl+D and Ctrl+U glide through intermediate views to native destinations", function()
  local screen = editor()
  for _, key in ipairs({ "<C-d>", "<C-u>" }) do
    screen:exec([[
      vim.wait(200)
      _G.scroll_start = vim.fn.winsaveview()
      vim.b.snacks_scroll = false
    ]])
    screen:input(key)
    local target = screen:exec("return vim.fn.winsaveview()")
    screen:exec([[
      vim.fn.winrestview(_G.scroll_start)
      vim.b.snacks_scroll = nil
    ]])
    vim.wait(200)
    local before = screen:exec("return vim.fn.line('w0')")
    screen:input(key)
    vim.wait(45)
    local during = screen:exec("return vim.fn.line('w0')")
    assert(during ~= before and during ~= target.topline, "half-page scroll did not visibly glide")
    h.wait(screen, function()
      return screen:exec("return vim.fn.line('w0')") == target.topline
        and screen:exec("return vim.fn.line('.')") == target.lnum
    end, "half-page glide missed the native destination")
    vim.wait(200)
    screen:exec("assert(vim.wo.virtualedit == '' and vim.wo.scrolloff == vim.o.scrolloff)")
  end
  screen:close()
end)

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

lib.test("scroll repeated half-pages and editing keys do not lose movement", function()
  local screen = editor()
  screen:exec([[
    _G.scroll_start = vim.fn.winsaveview()
    vim.b.snacks_scroll = false
  ]])
  screen:input("<C-d><C-d><C-u>j")
  local target = screen:exec("return vim.fn.winsaveview()")
  screen:exec([[
    vim.fn.winrestview(_G.scroll_start)
    vim.b.snacks_scroll = nil
  ]])
  vim.wait(200)
  for _, key in ipairs({ "<C-d>", "<C-d>", "<C-u>", "j" }) do
    screen:input(key)
    vim.wait(40)
  end
  vim.wait(250)
  lib.eq(target.lnum, screen:exec("return vim.fn.line('.')"), "input was lost during a half-page glide")
  lib.eq(target.topline, screen:exec("return vim.fn.line('w0')"), "repeated scroll ended at the wrong view")
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
