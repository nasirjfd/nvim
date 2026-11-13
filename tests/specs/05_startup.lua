-- Things that must already be in place right after startup.
local lib = require("lib")
local h = require("support")

for _, source in ipairs({ "grep", "recent" }) do
  lib.test("startup explorer does not close an immediately opened " .. source .. " popup", function()
    local dir = h.tmpdir()
    h.write(dir .. "/sample.txt", { "something to find" })
    local screen = h.nvim(dir, 160, 45, { ".", "-c", [[lua vim.api.nvim_create_autocmd('VimEnter', {
      once = true,
      callback = function()
        local git = require('snacks.explorer.git')
        local update = git.update
        git.update = function() end
        _G.explorer_git_ready = {}
        vim.defer_fn(function()
          git.update = update
          _G.explorer_git_ready[vim.fs.normalize(vim.fn.getcwd())] = true
          _G.startup_discovery_done = true
        end, 700)
      end,
    })]] })
    if source == "grep" then
      screen:input("<Space>/")
    else
      screen:exec("vim.v.oldfiles = { ... }", { dir .. "/sample.txt" })
      screen:exec("vim.fn.maparg('<D-e>', 'n', false, true).callback()")
    end
    h.wait(screen, function()
      return screen:exec([[
        _G.startup_popup = Snacks.picker.get({ source = ... })[1]
        return _G.startup_popup ~= nil
      ]], { source })
    end, "popup did not open")
    h.wait(screen, function()
      return screen:exec("return _G.startup_discovery_done == true")
    end, "directory discovery did not finish")
    vim.wait(1000)
    lib.ok(screen:exec([[
      return not _G.startup_popup.closed and _G.startup_popup:is_focused()
        and #Snacks.picker.get({ source = 'explorer' }) == 0
    ]]), "late startup explorer closed or stole focus from the popup")
    screen:close()
  end)
end

lib.test("kulala is loaded at startup, so the first .http buffer (e.g. in a diff) gets its colours", function()
  local screen = h.nvim(h.tmpdir())
  h.wait(screen, function()
    return screen:exec("return package.loaded['kulala'] ~= nil")
  end, "kulala did not load at startup")
  screen:close()
end)

lib.test("an .http file is highlighted by tree-sitter on first open", function()
  local dir = h.tmpdir()
  h.write(dir .. "/r.http", { "GET https://example.com/api HTTP/1.1", "Accept: application/json" })
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit r.http')")
  h.wait(screen, function()
    return screen:exec("return vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil")
  end, "tree-sitter never started on the .http buffer")
  screen:close()
end)

lib.test("HTTP highlighting recovers after attachment failed, without reopening Neovim", function()
  local dir = h.tmpdir()
  h.write(dir .. "/r.http", { "POST https://example.com/api", "Content-Type: application/json", "", '{"id":1}' })
  local screen = h.nvim(dir)
  screen:exec([[
    vim.cmd('edit r.http')
    vim.treesitter.stop(0)
    _G.real_ts_start = vim.treesitter.start
    _G.ts_attempts = 0
    vim.treesitter.start = function(...)
      _G.ts_attempts = _G.ts_attempts + 1
      if _G.ts_attempts <= 3 then error('parser not ready yet') end
      return _G.real_ts_start(...)
    end
    require('core.http-highlight').ensure(0)
  ]])
  h.wait(screen, function()
    return screen:exec("return _G.ts_attempts >= 4 and vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil")
  end, "HTTP highlighting did not recover from delayed parser availability")
  screen:close()
end)

lib.test("HTTP highlighting reattaches on buffer display after being stopped", function()
  local dir = h.tmpdir()
  h.write(dir .. "/r.http", { "GET https://example.com/api" })
  local screen = h.nvim(dir)
  screen:exec([[
    vim.cmd('edit r.http')
    vim.treesitter.stop(0)
    vim.cmd('doautocmd BufWinEnter')
  ]])
  h.wait(screen, function()
    return screen:exec("return vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil")
  end, "HTTP highlighting did not restart on display")
  screen:close()
end)

lib.test("a file gets a scrollbar handle showing the current viewport", function()
  local dir = h.tmpdir()
  local lines = {}
  for i = 1, 100 do
    lines[i] = "line " .. i
  end
  h.write(dir .. "/long.txt", lines)
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit long.txt')")
  h.wait(screen, function()
    return screen:exec([[local ns = vim.api.nvim_get_namespaces().Scrollbar
      return ns ~= nil and #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) > 0]])
  end, "scrollbar handle did not render for a long file")
  screen:close()
end)
