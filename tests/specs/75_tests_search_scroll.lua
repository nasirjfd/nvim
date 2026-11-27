local lib = require("lib")
local h = require("support")

local function start()
  local php = { "<?php", "class SearchTest extends \\PHPUnit\\Framework\\TestCase", "{" }
  for i = 1, 90 do
    php[#php + 1] = ("    public function testNumber%03d() {}"):format(i)
  end
  php[#php + 1] = "}"
  local dir = h.repo({ ["tests/SearchTest.php"] = php, ["phpunit.xml"] = { "<phpunit/>" } })
  local screen = h.nvim(dir)
  screen:exec(([[
    require("modules.phpunit").configure({ root = %q, projects = { "." } })
    vim.cmd("edit tests/SearchTest.php")
    require("modules.phpunit.pane").toggle()
  ]]):format(dir))
  h.wait(screen, function()
    return screen:exec([[
      local p = require("modules.phpunit.pane")
      return p.weight(p.root_id() or "") >= 90 and #p.panes() == 1
    ]])
  end, "test methods were not discovered")
  return screen, dir
end

local function search(screen, text)
  screen:input("/")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'snacks_picker_input' and vim.fn.mode() == 'i'")
  end, "test search did not open")
  screen:input(text)
  h.wait(screen, function()
    return screen:exec(([[
      local p = require("modules.phpunit.pane").panes()[1]
      return p and p.input.filter.pattern == %q and not p:is_active()
    ]]):format(text))
  end, "test search did not finish")
end

local function select_kind(screen, kind)
  h.wait(screen, function()
    return screen:exec(([[
      local p = require("modules.phpunit.pane").panes()[1]
      if p:is_active() then return false end
      for i, item in ipairs(p:items()) do
        if item.kind == %q then p.list:move(i, true); return true end
      end
      return false
    ]]):format(kind))
  end, "search result did not appear")
end

lib.test("Tests search and selected result survive switching to Git and back", function()
  local screen = start()
  search(screen, "testNumber042")
  select_kind(screen, "test")
  local key = screen:exec("return require('modules.phpunit.pane').panes()[1]:current().key")
  screen:exec("vim.cmd('stopinsert'); vim.cmd('CodeDiff scm')")
  h.wait(screen, function()
    return screen:exec([[
      return require("codediff.ui.lifecycle").get_panel_view(vim.api.nvim_get_current_tabpage()) ~= nil
        and #require("modules.phpunit.pane").panes() == 0
    ]])
  end, "Git did not replace Tests")
  screen:exec("require('modules.phpunit.pane').toggle()")
  h.wait(screen, function()
    return screen:exec(([[
      local p = require("modules.phpunit.pane").panes()[1]
      return p and not p:is_active() and p.input.filter.pattern == "testNumber042"
        and (p:current() or {}).key == %q
    ]]):format(key))
  end, "Tests lost its search or selected result")
  screen:close()
end)

lib.test("Tests search survives closing and reopening its sidebar", function()
  local screen = start()
  search(screen, "testNumber042")
  select_kind(screen, "test")
  screen:exec("require('modules.phpunit.pane').show_hide()")
  h.wait(screen, function()
    return screen:exec("return #require('modules.phpunit.pane').panes() == 0")
  end, "Tests did not close")
  screen:exec("require('modules.phpunit.pane').toggle()")
  h.wait(screen, function()
    return screen:exec([[
      local p = require("modules.phpunit.pane").panes()[1]
      return p and not p:is_active() and p.input.filter.pattern == "testNumber042"
        and (p:current() or {}).kind == "test"
    ]])
  end, "closed Tests lost its query or selected test")
  screen:close()
end)

for _, kind in ipairs({ "test", "file" }) do
  lib.test("Tests search Enter leaves search mode and opens the " .. kind, function()
    local screen, dir = start()
    search(screen, kind == "test" and "testNumber042" or "SearchTest")
    select_kind(screen, kind)
    screen:input("<CR>")
    h.wait(screen, function()
      return screen:exec(([[
        local p = require("modules.phpunit.pane").panes()[1]
        return vim.api.nvim_buf_get_name(0) == %q and vim.fn.mode() == "n"
          and p and p.layout:is_hidden("input")
          and vim.api.nvim_win_get_cursor(0)[1] == %d
      ]]):format(dir .. "/tests/SearchTest.php", kind == "test" and 45 or 1))
    end, "Enter did not leave search and open the result")
    screen:close()
  end)
end

lib.test("Tests mouse wheel scrolls without changing the selected test", function()
  local screen = start()
  screen:input("e")
  select_kind(screen, "test")
  local before = screen:exec([[
    local p = require("modules.phpunit.pane").panes()[1]
    return { key = p:current().key, top = p.list.top, cursor = p.list.cursor }
  ]])
  local win = screen:exec([[
    local p = require("modules.phpunit.pane").panes()[1]
    return vim.api.nvim_win_get_position(p.list.win.win)
  ]])
  for _ = 1, 20 do
    screen:request("nvim_input_mouse", { "wheel", "down", "", 0, win[1] + 10, win[2] + 10 })
  end
  h.wait(screen, function()
    return screen:exec(([[
      local p = require("modules.phpunit.pane").panes()[1]
      return p.list.top > p.list.cursor and p.list.top > %d
    ]]):format(before.top))
  end, "wheel did not scroll Tests")
  lib.eq(before.key, screen:exec("return require('modules.phpunit.pane').panes()[1]:current().key"))
  lib.eq(
    before.cursor,
    screen:exec("return require('modules.phpunit.pane').panes()[1].list.cursor")
  )
  lib.eq(
    false,
    screen:exec([[
    local p = require("modules.phpunit.pane").panes()[1]
    return vim.wo[p.list.win.win].cursorline
  ]]),
    "an offscreen selection must not highlight a different test"
  )
  local top = screen:exec("return require('modules.phpunit.pane').panes()[1].list.top")
  screen:exec("require('modules.pane_kit').refresh(require('modules.phpunit.pane').panes()[1])")
  h.wait(screen, function()
    return screen:exec("return not require('modules.phpunit.pane').panes()[1]:is_active()")
  end, "Tests did not refresh")
  lib.eq(top, screen:exec("return require('modules.phpunit.pane').panes()[1].list.top"))
  lib.eq(before.key, screen:exec("return require('modules.phpunit.pane').panes()[1]:current().key"))
  screen:input("j")
  h.wait(screen, function()
    return screen:exec(([[
      local p = require("modules.phpunit.pane").panes()[1]
      return p.list.cursor == %d and p.list.top <= p.list.cursor
    ]]):format(before.cursor + 1))
  end, "keyboard did not resume from the selected test")
  local clicked = screen:exec([[
    local p = require("modules.phpunit.pane").panes()[1]
    local item = p.list:get(p.list.top + 9)
    return { key = item.key, line = item.line }
  ]])
  h.click(screen, win[1] + 10, win[2] + 10)
  h.wait(screen, function()
    return screen:exec(([[
      local p = require("modules.phpunit.pane").panes()[1]
      return p:current().key == %q and vim.api.nvim_win_get_cursor(0)[1] == %d
        and vim.bo.filetype == "php"
    ]]):format(clicked.key, clicked.line))
  end, "a real click did not select and open the pointed test")
  screen:close()
end)
