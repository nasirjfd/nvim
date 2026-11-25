local lib = require("lib")
local h = require("support")

lib.test(
  "Option Shift F formats a large PHP selection synchronously without running Pint",
  function()
    local dir = h.tmpdir()
    local lines = { "<?php" }
    for _ = 1, 20000 do
      lines[#lines + 1] = "$value=1;"
    end
    h.write(dir .. "/large.php", lines)
    local screen = h.nvim(dir)
    screen:exec([[
    vim.cmd('edit large.php')
    local conform = require('conform')
    conform.formatters_by_ft.php = { 'selection_must_not_run' }
    conform.formatters.selection_must_not_run = {
      command = 'sh', args = { '-c', 'exit 91' }, stdin = true,
    }
    _G.format_calls = {}
    vim.lsp.start({
      name = 'fast-range-test', root_dir = vim.fn.getcwd(),
      cmd = function(dispatchers)
        local closing = false
        return {
          request = function(method, params, callback)
            vim.schedule(function()
              if method == 'initialize' then
                callback(nil, { capabilities = { documentRangeFormattingProvider = true } })
              elseif method == 'textDocument/rangeFormatting' then
                table.insert(_G.format_calls, params.range)
                callback(nil, { {
                  range = { start = { line = 10000, character = 0 }, ['end'] = { line = 10000, character = 9 } },
                  newText = '$value = 1;',
                } })
              else
                callback(nil, nil)
              end
            end)
            return true, 1
          end,
          notify = function() return true end,
          is_closing = function() return closing end,
          terminate = function() closing = true; dispatchers.on_exit(0, 0) end,
        }
      end,
    })
  ]])
    h.wait(screen, function()
      return screen:exec(
        "local c = vim.lsp.get_clients({ name = 'fast-range-test' })[1]; return c and c.initialized"
      )
    end, "range formatter did not initialize")
    screen:exec([[
    _G.format_sync = nil
    local format = require('core.format').format
    require('core.format').format = function()
      format()
      _G.format_sync = vim.api.nvim_buf_get_lines(0, 10000, 10001, false)[1] == '$value = 1;'
    end
    vim.api.nvim_win_set_cursor(0, { 10001, 0 })
  ]])
    screen:input("V<M-F>")
    h.wait(screen, function()
      return screen:exec("return _G.format_sync ~= nil")
    end, "format shortcut did not return")
    lib.ok(
      screen:exec("return _G.format_sync"),
      "format returned before applying the selected text"
    )
    lib.eq(
      1,
      screen:exec("return #_G.format_calls"),
      "format did not use exactly one range request"
    )
    lib.eq(10000, screen:exec("return _G.format_calls[1].start.line"))
    lib.eq(10000, screen:exec("return _G.format_calls[1]['end'].line"))
    lib.eq("$value=1;", screen:exec("return vim.api.nvim_buf_get_lines(0, 9999, 10000, false)[1]"))
    lib.eq(20001, screen:exec("return vim.api.nvim_buf_line_count(0)"))
    screen:close()
  end
)

lib.test(
  "manual whole-file formatting stays synchronous with the configured CLI formatter",
  function()
    local dir = h.tmpdir()
    h.write(dir .. "/example.lua", { "local a={1,2}" })
    local screen = h.nvim(dir)
    local formatted = screen:exec([[
    vim.cmd('edit example.lua')
    require('core.format').format()
    return vim.api.nvim_get_current_line()
  ]])
    lib.eq(
      "local a = { 1, 2 }",
      formatted,
      "whole-file formatting returned before CLI edits were applied"
    )
    screen:close()
  end
)

lib.test(
  "selection formatting falls back to a range-capable CLI without an LSP formatter",
  function()
    local dir = h.tmpdir()
    h.write(dir .. "/example.lua", { "local a={1,2}", "local b={3,4}" })
    local screen = h.nvim(dir)
    screen:exec("vim.cmd('edit example.lua'); vim.api.nvim_win_set_cursor(0, { 2, 0 })")
    screen:input("V<M-F>")
    h.wait(screen, function()
      return screen:exec(
        "return vim.api.nvim_buf_get_lines(0, 1, 2, false)[1] == 'local b = { 3, 4 }'"
      )
    end, "selection was not formatted without a range LSP")
    lib.eq("local a={1,2}", screen:exec("return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]"))
    screen:close()
  end
)
