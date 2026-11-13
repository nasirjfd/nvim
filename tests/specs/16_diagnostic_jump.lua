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
    return screen:exec([[
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
    ]], { text, line })
  end, "diagnostic jump did not show a readable box without stealing focus")
end

lib.test("diagnostic jumps show rounded readable boxes in both directions", function()
  local screen = editor()
  screen:input("]d")
  popup(screen, 2, "Error: test-server")
  screen:input("]d")
  popup(screen, 4, "Warning: test-server")
  screen:input("[d")
  popup(screen, 2, "Error: test-server")
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
