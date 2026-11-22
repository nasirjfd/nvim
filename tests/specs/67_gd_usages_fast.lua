-- gd on a declaration lists its usages without the wait of the language server (lua/core/usages.lua): they are
-- asked for while the cursor rests on the name, and when they are not in yet the list opens at once and fills in.
-- The fake server answers references after 1.5 s, like intelephense does for a common method name.
local lib = require("lib")
local h = require("support")

local DELAY = 1500

local function editor(usages)
  local dir = h.tmpdir()
  h.write(dir .. "/Journey.php", {
    "<?php",
    "class Journey {",
    "    public static function create(string $id): self", -- line 3, "create" at col 28 (0-based 27)
    "    {",
    "        return new self();",
    "    }",
    "}",
  })
  h.write(dir .. "/Use.php", { "<?php", "Journey::create('a');", "Journey::create('b');", "Journey::create('c');" })
  local screen = h.nvim(dir, 160, 40)
  screen:exec(string.format([[
    vim.g.autosave = false
    local dir, usages, delay = %q, %d, %d
    _G.reference_requests = 0
    vim.api.nvim_create_autocmd('FileType', { pattern = 'php', callback = function(ev)
      vim.lsp.start({
        name = 'usages-test', root_dir = dir,
        cmd = function(dispatchers)
          local closing, id = false, 0
          return {
            request = function(method, params, callback)
              id = id + 1
              local result, wait = nil, 0
              if method == 'initialize' then
                result = { capabilities = { definitionProvider = true, referencesProvider = true, textDocumentSync = 1 } }
              elseif method == 'textDocument/definition' then
                result = { uri = vim.uri_from_fname(dir .. '/Journey.php'), range = { start = { line = 2, character = 27 }, ['end'] = { line = 2, character = 33 } } }
              elseif method == 'textDocument/references' then
                _G.reference_requests = _G.reference_requests + 1
                result, wait = {}, delay
                for i = 1, usages do
                  result[i] = { uri = vim.uri_from_fname(dir .. '/Use.php'), range = { start = { line = i, character = 9 }, ['end'] = { line = i, character = 15 } } }
                end
              end
              vim.defer_fn(function() callback(nil, result) end, wait)
              return true, id
            end,
            notify = function() return true end,
            is_closing = function() return closing end,
            terminate = function() closing = true; dispatchers.on_exit(0, 0) end,
          }
        end,
      }, { bufnr = ev.buf })
    end })
    vim.cmd('edit ' .. dir .. '/Journey.php')
  ]], dir, usages, DELAY))
  h.wait(screen, function()
    return screen:exec("return #vim.lsp.get_clients({ bufnr = 0, name = 'usages-test' }) == 1 and vim.lsp.get_clients({ bufnr = 0, name = 'usages-test' })[1].initialized == true")
  end, "the language server did not attach")
  return screen
end

local function picker_count(screen)
  return screen:exec([[
    local p = Snacks.picker.get({ source = 'lsp_references' })[1]
    return p and p:count() or -1
  ]])
end

lib.test("gd on a declaration: usages fetched while the cursor rested there show at once", function()
  local screen = editor(3)
  screen:exec("vim.api.nvim_win_set_cursor(0, { 3, 30 })") -- inside "create"
  screen:exec("vim.api.nvim_exec_autocmds('CursorHold', { buffer = 0 })")
  h.wait(screen, function()
    return screen:exec([[
      for _, e in pairs(require('core.usages').entries()) do if e.done then return true end end
      return false
    ]])
  end, "the usages were not fetched ahead", DELAY + 3000)
  local start = vim.uv.hrtime()
  screen:input("gd")
  h.wait(screen, function()
    return picker_count(screen) == 3
  end, "gd did not list the three usages")
  local took = (vim.uv.hrtime() - start) / 1e6
  lib.ok(took < 700, ("the usages took %d ms: they were fetched already"):format(took))
  lib.eq(1, screen:exec("return _G.reference_requests"), "asked once, not again for gd")
  screen:close()
end)

lib.test("gd on a declaration: without them yet, the list opens at once and fills in when they come", function()
  local screen = editor(3)
  screen:exec("vim.api.nvim_win_set_cursor(0, { 3, 30 })")
  local start = vim.uv.hrtime()
  screen:input("gd")
  h.wait(screen, function()
    return picker_count(screen) >= 0
  end, "the references list did not open before the server answered", DELAY - 300)
  lib.ok((vim.uv.hrtime() - start) / 1e6 < DELAY, "opened before the answer")
  h.wait(screen, function()
    return picker_count(screen) == 3
  end, "the usages did not fill in", DELAY + 3000)
  screen:close()
end)

lib.test("gd on a declaration with one usage goes there; on a usage gd still goes to the definition", function()
  local screen = editor(1)
  screen:exec("vim.api.nvim_win_set_cursor(0, { 3, 30 })")
  screen:input("gd")
  h.wait(screen, function()
    return screen:exec("return vim.fn.expand('%:t')") == "Use.php" and screen:exec("return vim.api.nvim_win_get_cursor(0)[1]") == 2
  end, "the only usage was not opened", DELAY + 3000)
  -- on the usage: the definition, right away
  screen:exec("vim.api.nvim_win_set_cursor(0, { 2, 11 })")
  screen:input("gd")
  h.wait(screen, function()
    return screen:exec("return vim.fn.expand('%:t')") == "Journey.php" and screen:exec("return vim.api.nvim_win_get_cursor(0)[1]") == 3
  end, "gd on a usage did not go to the definition")
  screen:close()
end)

lib.test("usages: only a declaration's name is fetched ahead, never any other word", function()
  local screen = editor(3)
  screen:exec("vim.api.nvim_win_set_cursor(0, { 5, 10 })") -- "return": not a declaration name
  screen:exec("vim.api.nvim_exec_autocmds('CursorHold', { buffer = 0 })")
  screen:exec("vim.api.nvim_win_set_cursor(0, { 3, 40 })") -- the parameter's type, inside the declaration
  screen:exec("vim.api.nvim_exec_autocmds('CursorHold', { buffer = 0 })")
  vim.wait(300) -- nothing must be asked
  lib.eq(0, screen:exec("return _G.reference_requests"))
  screen:close()
end)
