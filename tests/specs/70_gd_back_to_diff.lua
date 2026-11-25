local lib = require("lib")
local h = require("support")

-- gd in a Git diff opens the file in an editor tab and jumps to the definition there; one Ctrl+O
-- from where it landed goes back to the diff (not to the editor copy of the file gd started in).

-- A language server whose every definition is `target` (file name relative to the cwd, 1-based line).
local function fake_definitions(screen)
  screen:exec([[
    _G.definition_target = { file = 'b.txt', line = 1 }
    local config = {
      name = 'definition-test', root_dir = vim.fn.getcwd(),
      cmd = function(dispatchers)
        local closing = false
        return {
          request = function(method, _, callback)
            vim.schedule(function()
              if method == 'initialize' then
                callback(nil, { capabilities = { definitionProvider = true } })
              elseif method == 'textDocument/definition' then
                local t = _G.definition_target
                callback(nil, {
                  uri = vim.uri_from_fname(vim.fn.getcwd() .. '/' .. t.file),
                  range = { start = { line = t.line - 1, character = 0 }, ['end'] = { line = t.line - 1, character = 0 } },
                })
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
    }
    local function attach(buf)
      if vim.bo[buf].buftype == '' and vim.api.nvim_buf_get_name(buf):match('%.txt$') then
        vim.lsp.start(config, { bufnr = buf })
      end
    end
    vim.api.nvim_create_autocmd('BufEnter', { pattern = '*.txt', callback = function(ev) attach(ev.buf) end })
  ]])
end

-- Open the commit diff of a.txt from the graph, cursor on its first change (line 7), and remember it.
local function open_commit_diff(screen)
  screen:exec("vim.cmd('CodeDiff graph')")
  h.wait(screen, function()
    return screen:exec(
      [[local g = require('codediff.ui.graph').get(vim.api.nvim_get_current_tabpage()); return g and g.details and next(g.details.files or {}) ~= nil]]
    )
  end, "graph not ready")
  screen:input("<CR><CR>")
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      return s and s.refresh and not s.refresh.loading and not s.refresh.running
        and vim.api.nvim_get_current_win() == s.modified_win and vim.api.nvim_win_get_cursor(0)[1] == 7
    ]])
  end, "commit diff did not settle on the first change")
  screen:exec([[
    _G.diff_tab = vim.api.nvim_get_current_tabpage()
    _G.diff_win = vim.api.nvim_get_current_win()
  ]])
end

local function back_in_diff(screen)
  return screen:exec(
    "return vim.api.nvim_get_current_win() == _G.diff_win and vim.api.nvim_win_get_cursor(0)[1] == 7"
  )
end

lib.test("Ctrl+O after gd in a Git diff goes straight back to the diff", function()
  local lines = { "one", "two", "three", "four", "five", "six", "seven", "eight" }
  local dir = h.repo({ ["a.txt"] = lines, ["b.txt"] = { "target" } })
  lines[7] = "changed"
  h.write(dir .. "/a.txt", lines)
  h.git(dir, "commit", "-qam", "change")
  local screen = h.nvim(dir)
  fake_definitions(screen)
  -- the server is running before the diff, like intelephense in a real project
  screen:exec("vim.cmd('edit b.txt'); vim.cmd('edit a.txt')")
  h.wait(screen, function()
    return screen:exec(
      "local c = vim.lsp.get_clients({ name = 'definition-test' })[1]; return c ~= nil and c.initialized == true"
    )
  end, "the language server did not start")
  open_commit_diff(screen)

  -- a definition in another file
  screen:input("gd")
  h.wait(screen, function()
    return screen:exec(
      "return vim.api.nvim_get_current_tabpage() ~= _G.diff_tab and vim.fn.expand('%:t') == 'b.txt'"
    )
  end, function()
    return "gd did not reach the definition in b.txt: "
      .. vim.inspect(screen:exec([[
        local m = vim.fn.maparg('gd', 'n', false, true)
        return { tab = vim.api.nvim_get_current_tabpage(), diff = _G.diff_tab, file = vim.fn.expand('%:p'),
          map = m.desc or m.rhs, buffer = m.buffer, clients = #vim.lsp.get_clients({ bufnr = 0 }),
          wins = #vim.api.nvim_tabpage_list_wins(0), tabs = #vim.api.nvim_list_tabpages(),
          msgs = vim.fn.execute('messages') }
      ]]))
  end)
  screen:input("<C-o>")
  h.wait(screen, function()
    return back_in_diff(screen)
  end, function()
    return "Ctrl+O did not return to the diff: "
      .. vim.inspect(screen:exec("return { file = vim.fn.expand('%:t'), line = vim.fn.line('.') }"))
  end)
  lib.ok(
    screen:exec(
      "return vim.api.nvim_tabpage_is_valid(_G.diff_tab) and vim.api.nvim_win_is_valid(_G.diff_win)"
    ),
    "the diff was closed"
  )

  -- a definition in the same file
  screen:exec("_G.definition_target = { file = 'a.txt', line = 2 }")
  screen:input("gd")
  h.wait(screen, function()
    return screen:exec(
      "return vim.api.nvim_get_current_tabpage() ~= _G.diff_tab and vim.fn.expand('%:t') == 'a.txt' and vim.fn.line('.') == 2"
    )
  end, "gd did not reach the definition on line 2 of a.txt")
  screen:input("<C-o>")
  h.wait(screen, function()
    return back_in_diff(screen)
  end, function()
    return "Ctrl+O did not return to the diff: "
      .. vim.inspect(screen:exec("return { file = vim.fn.expand('%:t'), line = vim.fn.line('.') }"))
  end)
  screen:close()
end)
