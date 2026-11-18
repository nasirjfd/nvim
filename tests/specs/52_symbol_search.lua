local lib = require("lib")
local h = require("support")

lib.test("cmd+f12 and cmd+shift+f12 search symbols with the selection in any mode", function()
  local dir = h.tmpdir()
  h.write(dir .. "/a.lua", { "local fooBar = 1" })
  local screen = h.nvim(dir, 100, 20)
  screen:exec([[
    vim.cmd("edit a.lua")
    _G.calls = {}
    Snacks.picker.lsp_symbols = function(o) table.insert(_G.calls, { "doc", o and o.pattern }) end
    Snacks.picker.lsp_workspace_symbols = function(o) table.insert(_G.calls, { "ws", o and o.search }) end
  ]])
  local function press(keys)
    screen:exec(("vim.api.nvim_feedkeys(vim.keycode(%q), 'x', false)"):format(keys))
  end
  press("<D-F12>")
  press("<D-S-F12>")
  press("wviw<D-F12>")
  press("0wviw<D-S-F12>")
  press("0wviw<leader>lS")
  press("A<D-F12>")
  local calls = screen:exec("return _G.calls")
  lib.eq(calls, {
    { "doc" },
    { "ws" },
    { "doc", "fooBar" },
    { "ws", "fooBar" },
    { "ws", "fooBar" },
    { "doc" },
  })
end)
