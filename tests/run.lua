-- Run with:  tests/run.sh [filter]     (nvim -l tests/run.lua)
-- Every spec drives a real Neovim with this configuration, embedded and rendered, so what is asserted is
-- what is on the screen.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/tests/?.lua;" .. package.path
vim.env.NVIM_CONFIG_TESTS = "1" -- no network, no automatic plugin updates (lua/core/lazy.lua)

local lib = require("lib")
local filter = arg and arg[1]
for _, file in ipairs(vim.fn.sort(vim.fn.glob(root .. "/tests/specs/*.lua", false, true))) do
  print("\n" .. vim.fn.fnamemodify(file, ":t"))
  dofile(file)
end
local ok = lib.run(filter)
vim.cmd(ok and "qa!" or "cq!")
