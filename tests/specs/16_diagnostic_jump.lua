local lib = require("lib")
local h = require("support")

local function editor()
  local screen = h.nvim(h.tmpdir())
  screen:exec([[
    vim.cmd('enew')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'first', 'broken', 'middle', 'warning', 'last' })
    local ns = vim.api.nvim_create_namespace('DiagnosticJumpTest')
    vim.diagnostic.set(ns, 0, {
      { lnum = 1, col = 0, severity = vim.diagnostic.severity.ERROR,
        message = 'An error that needs attention. ' .. string.rep('More context to read comfortably. ', 8),
        source = 'test-server' },
      { lnum = 3, col = 0, severity = vim.diagnostic.severity.WARN,
        message = 'A warning worth reading', source = 'test-server' },
    })
    _G.diagnostic_editor = vim.api.nvim_get_current_win()
  ]])
  return screen
end

local function popup(screen, line, text)
  h.wait(screen, function()
    return screen:exec(
      [[
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= '' and config.title then
          local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
          if table.concat(lines, '\n'):find(..., 1, true) then
            return vim.api.nvim_get_current_win() == _G.diagnostic_editor
              and vim.api.nvim_win_get_cursor(0)[1] == select(2, ...)
              and config.width <= 88 and vim.wo[win].wrap
              and config.border[1] == '╭'
          end
        end
      end
      return false
    ]],
      { text, line }
    )
  end, "diagnostic jump did not show a readable box without stealing focus")
end

lib.test("diagnostic jumps show rounded readable boxes in both directions", function()
  local screen = editor()
  screen:input("]d")
  popup(screen, 2, "An error that needs attention")
  screen:input("]d")
  popup(screen, 4, "A warning worth reading")
  screen:input("[d")
  popup(screen, 2, "An error that needs attention")
  screen:input("j")
  h.wait(screen, function()
    return screen:exec([[
      local win = vim.b.lsp_floating_preview
      return not win or not vim.api.nvim_win_is_valid(win)
    ]])
  end, "diagnostic box stayed open after moving away")
  screen:close()
end)

lib.test("diagnostic jump with no diagnostics does not open an empty box", function()
  local screen = editor()
  screen:exec("vim.diagnostic.reset()")
  screen:input("]d[d")
  lib.ok(screen:exec("return vim.b.lsp_floating_preview == nil"), "empty diagnostic popup opened")
  screen:close()
end)

lib.test("diagnostic jump card survives offscreen jumps and queued cursor events", function()
  local screen = editor()
  screen:exec([[
    vim.diagnostic.reset()
    local lines = {}
    for i = 1, 1000 do lines[i] = 'line ' .. i end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.diagnostic.set(vim.api.nvim_create_namespace('FarDiagnostics'), 0, {
      { lnum = 99, col = 0, message = 'First distant error', severity = 1 },
      { lnum = 799, col = 0, message = 'Second distant error', severity = 1 },
    })
  ]])
  for i = 1, 30 do
    local key = i % 3 == 0 and "[d" or "]d"
    local expected = screen:exec(
      [[
      local d = (...) == ']d' and vim.diagnostic.get_next() or vim.diagnostic.get_prev()
      return d.lnum + 1
    ]],
      { key }
    )
    screen:input(key)
    popup(screen, expected, "distant error")
    vim.wait(i % 4 == 0 and 180 or 15)
    screen:exec("vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })")
    lib.ok(
      screen:exec([[
      local win = vim.b.lsp_floating_preview
      return win and vim.api.nvim_win_is_valid(win) and vim.b.snacks_scroll == false
    ]]),
      "card vanished after diagnostic jump " .. i
    )
  end
  screen:input("<Esc>")
  h.wait(screen, function()
    return screen:exec("return vim.b.snacks_scroll == nil")
  end, "Escape did not restore smooth scrolling")
  screen:close()
end)

local function attach_inline(screen)
  h.wait(screen, function()
    return screen:exec("return package.loaded['tiny-inline-diagnostic'] ~= nil")
  end, "inline diagnostic plugin did not load")
  screen:exec([[
    vim.api.nvim_exec_autocmds('LspAttach', { buffer = 0, data = { client_id = 0 } })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
  ]])
  h.wait(screen, function()
    return screen:exec([[
      local ns = vim.api.nvim_get_namespaces().TinyInlineDiagnostic
      return ns and #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) > 0
    ]])
  end, "inline diagnostic did not appear")
end

lib.test("diagnostic jump card hides duplicate inline text and restores it on Escape", function()
  local screen = editor()
  attach_inline(screen)
  screen:input("[d")
  popup(screen, 4, "A warning worth reading")
  vim.wait(100)
  lib.ok(
    screen:exec([[
    local ns = vim.api.nvim_get_namespaces().TinyInlineDiagnostic
    return #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 0
      and not require('tiny-inline-diagnostic.state').user_toggle_state
      and #vim.diagnostic.get(0) == 2
  ]]),
    "inline text duplicated the card or diagnostics were removed"
  )
  screen:input("<Esc>")
  h.wait(screen, function()
    return screen:exec([[
      local ns = vim.api.nvim_get_namespaces().TinyInlineDiagnostic
      return require('tiny-inline-diagnostic.state').user_toggle_state
        and #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) > 0
        and vim.b.snacks_scroll == nil
    ]])
  end, "inline diagnostics did not return after Escape")
  screen:close()
end)

lib.test("diagnostic jump card preserves disabled inline diagnostics and scrolling", function()
  local screen = editor()
  attach_inline(screen)
  screen:exec("require('tiny-inline-diagnostic').disable(); vim.b.snacks_scroll = false")
  screen:input("]d")
  popup(screen, 4, "A warning worth reading")
  screen:input("<Esc>")
  vim.wait(100)
  lib.ok(
    screen:exec([[
    return not require('tiny-inline-diagnostic.state').user_toggle_state
      and vim.b.snacks_scroll == false
  ]]),
    "closing the card changed the user's disabled settings"
  )
  screen:close()
end)

lib.test(
  "diagnostic jump card restores inline diagnostics after rapid alternating jumps",
  function()
    local screen = editor()
    attach_inline(screen)
    screen:input(string.rep("]d[d", 20))
    vim.wait(200)
    popup(screen, 2, "An error that needs attention")
    screen:input("j")
    h.wait(screen, function()
      return screen:exec([[
      return require('tiny-inline-diagnostic.state').user_toggle_state and vim.b.snacks_scroll == nil
    ]])
    end, "rapid jumps leaked popup/inline state")
    screen:close()
  end
)
