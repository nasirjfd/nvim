local lib = require("lib")
local h = require("support")

lib.test("workspace symbols are cached per query and refreshed in the background after a save", function()
  local dir = h.tmpdir()
  h.write(dir .. "/a.lua", { "x" })
  local screen = h.nvim(dir)
  screen:exec(
    [[
    local dir = ...
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.lua'))
    _G.requests = 0
    require('core.symbol-files').clients = function()
      return { { id = 1, root_dir = dir, offset_encoding = 'utf-16',
        supports_method = function(_, m) return m == 'workspace/symbol' end } }
    end
    require('snacks.picker.source.lsp').request = function(_, _, params, cb)
      _G.requests = _G.requests + 1
      cb({ offset_encoding = 'utf-16' }, { { name = 'Sym', kind = 12, location = {
        uri = vim.uri_from_fname(dir .. '/a.lua'), range = {
          start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 1 } } } } }, params())
    end
  ]],
    { dir }
  )
  local function open_and_count()
    screen:exec("require('core.symbol-search').open(true)")
    h.wait(screen, function()
      return screen:exec([[
        local p = Snacks.picker.get({ source = 'lsp_workspace_symbols' })[1]
        return p and not p.finder:running() and not p.matcher:running() and p:count() == 1
      ]])
    end, "workspace picker did not list the symbol")
    screen:exec("Snacks.picker.get({ source = 'lsp_workspace_symbols' })[1]:close()")
    return screen:exec("return _G.requests")
  end
  lib.eq(open_and_count(), 1)
  lib.eq(open_and_count(), 1) -- served from the cache
  screen:exec("vim.cmd('silent write')")
  screen:exec("require('core.symbol-search').open(true)")
  h.wait(screen, function() -- the stale answer is shown at once...
    return screen:exec([[
      local p = Snacks.picker.get({ source = 'lsp_workspace_symbols' })[1]
      return p and not p.finder:running() and p:count() == 1
    ]])
  end, "stale answer not shown")
  lib.eq(screen:exec("return _G.requests"), 1)
  h.wait(screen, function() -- ...and refreshed behind it
    return screen:exec("return _G.requests") == 2
  end, "the stale answer was not refreshed")
end)
