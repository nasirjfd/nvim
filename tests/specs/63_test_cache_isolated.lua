-- Tests never write into the real ~/.cache/nvim/luac: every test loads the plugins from its own temporary
-- path and Neovim's bytecode cache keeps one file per path forever (it grew to millions of files).
local lib = require("lib")
local h = require("support")

lib.test("a test's editor keeps its Lua bytecode cache out of the real cache directory", function()
  local real_luac = lib.real_cache .. "/luac"
  local function test_entries()
    local n = 0
    for _, name in ipairs(vim.fn.isdirectory(real_luac) == 1 and vim.fn.readdir(real_luac) or {}) do
      if name:find("%-state%%2fdata", 1) then
        n = n + 1
      end
    end
    return n
  end
  local before = test_entries()
  local screen = h.nvim(h.tmpdir(), 80, 20)
  local cache = screen:exec("return vim.fn.stdpath('cache')")
  lib.matches("%-state/cache/nvim$", cache, "the editor's cache directory is the test's own")
  lib.ok(screen:exec("return vim.loader.enabled") == true, "the bytecode cache is on in the test")
  h.wait(screen, function()
    return vim.fn.isdirectory(cache .. "/luac") == 1 and #vim.fn.readdir(cache .. "/luac") > 0
  end, "the editor wrote no bytecode into the test's own cache")
  lib.eq(before, test_entries(), "the test added bytecode files to the real cache")
end)
