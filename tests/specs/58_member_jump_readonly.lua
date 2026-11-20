local lib = require("lib")
local h = require("support")

-- Shift+U / Shift+S jump between classes and methods in a read-only buffer without a language
-- server (a diff's revision: treesitter started with a language, no filetype), and never fail
-- with E21 there.

local PHP = {
  "<?php",
  "class A",
  "{",
  "    public function one()",
  "    {",
  "        return 1;",
  "    }",
  "",
  "    public function two()",
  "    {",
  "        return 2;",
  "    }",
  "}",
}

local function revision(screen, lines, lang)
  screen:exec(([[
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, %s)
    vim.bo[buf].modifiable = false
    vim.bo[buf].readonly = true
    vim.api.nvim_win_set_buf(0, buf)
    if %q ~= "" then
      vim.treesitter.start(buf, %q)
    end
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.v.errmsg = ""
  ]]):format(vim.inspect(lines), lang, lang))
end

local function cursor_row(screen)
  return screen:exec("return vim.api.nvim_win_get_cursor(0)[1]")
end

lib.test("Shift+S / Shift+U move between members of a read-only revision with treesitter", function()
  local screen = h.nvim(h.tmpdir())
  revision(screen, PHP, "php")
  screen:input("S")
  h.wait(screen, function()
    return cursor_row(screen) == 2
  end, "S did not go to the class")
  screen:input("S")
  h.wait(screen, function()
    return cursor_row(screen) == 4
  end, "S did not go to the first method")
  screen:input("S")
  h.wait(screen, function()
    return cursor_row(screen) == 9
  end, "S did not go to the second method")
  screen:input("U")
  h.wait(screen, function()
    return cursor_row(screen) == 4
  end, "U did not go back to the first method")
  lib.eq("", screen:exec("return vim.v.errmsg"))
  screen:close()
end)

lib.test("Shift+S / Shift+U do nothing in a read-only buffer without members, no E21", function()
  local screen = h.nvim(h.tmpdir())
  revision(screen, { "plain", "text" }, "")
  screen:input("S")
  screen:input("U")
  vim.wait(200) -- nothing else happens
  lib.eq("", screen:exec("return vim.v.errmsg"))
  lib.eq(1, cursor_row(screen))
  screen:close()
end)
