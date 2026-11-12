-- o / O follow the indentation the file already uses (4 spaces, 2 spaces, tabs), not the global default.
local lib = require("lib")
local h = require("support")

local guess = require("core.guess-indent").detect

lib.test("guess indent: the width is the most common step between lines, tabs win when most lines have one", function()
  lib.eq({ expandtab = true, width = 4 }, guess({ "a {", "    b {", "        c", "    }", "}" }))
  lib.eq({ expandtab = true, width = 2 }, guess({ "a {", "  b {", "    c", "  }", "}" }))
  lib.eq({ expandtab = false }, guess({ "a {", "\tb {", "\t\tc", "\t}", "}" }))
  lib.eq(nil, guess({ "no", "indent", "here" }))
  lib.eq(nil, guess({}))
  -- the lines of a /* */ block start with " *": that is not an indent of 1
  lib.eq({ expandtab = true, width = 4 }, guess({ "/**", " * doc", " */", "f {", "    x", "}" }))
end)

local function o_result(screen, name, lines, row, key)
  local dir = h.tmpdir()
  h.write(dir .. "/" .. name, lines)
  screen:exec("vim.cmd('edit ' .. vim.fn.fnameescape(...))", { dir .. "/" .. name })
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype") ~= ""
  end, "no filetype")
  screen:exec("vim.wait(300)")
  return screen:exec([[
    local row, key = ...
    vim.api.nvim_win_set_cursor(0, { row, 0 })
    vim.cmd("normal! " .. key .. "X")
    local target = key == "o" and row + 1 or row
    return vim.api.nvim_buf_get_lines(0, target - 1, target, false)[1]
  ]], { row, key })
end

lib.test("guess indent: o and O in a 4-space file and in a 2-space file follow the file", function()
  local screen = h.nvim(h.tmpdir())
  local four = { "local t = {", "    a = 1,", "    b = 2,", "}", "local function f()", "    if x then", "        y()", "    end", "end" }
  lib.eq("    X", o_result(screen, "four.lua", four, 2, "o"), "o after a table entry, 4 spaces")
  lib.eq("        X", o_result(screen, "four2.lua", four, 6, "o"), "o after `if x then`, 4 spaces")
  local two = { "local t = {", "  a = 1,", "  b = 2,", "}", "local function f()", "  if x then", "    y()", "  end", "end" }
  lib.eq("  X", o_result(screen, "two.lua", two, 2, "o"), "o after a table entry, 2 spaces")
  lib.eq("    X", o_result(screen, "two2.lua", two, 6, "o"), "o after `if x then`, 2 spaces")
  screen:close()
end)
