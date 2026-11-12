-- Things that must already be in place right after startup.
local lib = require("lib")
local h = require("support")

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
