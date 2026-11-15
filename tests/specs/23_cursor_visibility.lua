local lib = require("lib")
local h = require("support")

local function editor()
  local lines = {}
  for i = 1, 300 do
    lines[i] = "line " .. i
  end
  local dir =
    h.repo({ ["a.txt"] = lines, ["a.http"] = { "### request", "GET https://example.com" } })
  lines[20] = "changed"
  h.write(dir .. "/a.txt", lines)
  local screen = h.nvim(dir, 180, 45, { "a.txt" })
  screen:exec([[
    _G.editor_win = vim.api.nvim_get_current_win()
    _G.normal_cursor = vim.o.guicursor
    _G.wheel_seen = 0
    vim.on_key(function(key, typed)
      if vim.fn.keytrans(typed and typed ~= '' and typed or key):find('ScrollWheel', 1, true) then
        _G.wheel_seen = _G.wheel_seen + 1
      end
    end, vim.api.nvim_create_namespace('cursor-test-wheel'))
  ]])
  return screen
end

local function hidden(screen, want)
  h.wait(screen, function()
    return screen:exec("return vim.o.guicursor:find('HiddenCursor', 1, true) ~= nil") == want
  end, want and "navigation cursor must be hidden" or "text cursor must be restored")
end

lib.test("cursor is visible in filename and text prompts opened from a hidden sidebar", function()
  local screen = editor()
  screen:exec("Snacks.explorer()")
  hidden(screen, true)
  screen:exec([[
    _G.filename_input = Snacks.input({ prompt = 'Paste as', default = 'copy.php' }, function() end)
  ]])
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'snacks_input' and vim.fn.mode() == 'i'")
  end, "filename prompt did not get input focus")
  hidden(screen, false)
  screen:exec("vim.cmd('stopinsert')")
  h.wait(screen, function()
    return screen:exec("return vim.fn.mode() == 'n'")
  end, "filename prompt did not leave insert mode")
  screen:exec("vim.cmd('normal! 0v3l' .. vim.keycode('<C-g>'))")
  h.wait(screen, function()
    return screen:exec("return vim.fn.mode() == 's'")
  end, function()
    return "filename stem was not selected: " .. screen:exec("return vim.fn.mode()")
  end)
  hidden(screen, false)
  screen:input("renamed")
  hidden(screen, false)
  screen:exec("_G.filename_input:execute('cancel')")
  hidden(screen, true)
  screen:close()
end)

for _, pane in ipairs({
  { name = "Explorer", open = "Snacks.explorer()", source = "explorer" },
  { name = "HTTP", open = "require('modules.http_requests').toggle()", source = "http_requests" },
  { name = "Tests", open = "require('modules.phpunit.pane').toggle()", source = "phpunit_tests" },
  { name = "Git", open = "vim.cmd('CodeDiff scm')", ft = "codediff-explorer" },
  { name = "Git graph", open = "vim.cmd('CodeDiff graph')", ft = "codediff-graph" },
  {
    name = "Commit details",
    open = "vim.cmd('CodeDiff graph')",
    ft = "codediff-graph",
    details = true,
  },
}) do
  lib.test(
    "cursor is hidden in " .. pane.name .. " and immediately restored in text after scrolling",
    function()
      local screen = editor()
      screen:exec(pane.open)
      h.wait(screen, function()
        if pane.source then
          return screen:exec(
            [[
          for _, p in ipairs(Snacks.picker.get({source = ...})) do
            if p.list.win.win == vim.api.nvim_get_current_win() then return true end
          end
          return false
        ]],
            { pane.source }
          )
        end
        return screen:exec("return vim.bo.filetype") == pane.ft
      end, pane.name .. " did not get focus")
      if pane.details then
        h.wait(screen, function()
          return screen:exec([[
          local g = require('codediff.ui.graph').get()
          return g and g.details and next(g.details.files or {}) ~= nil
        ]])
        end, "commit details did not load")
        screen:input("<CR>")
        h.wait(screen, function()
          return screen:exec("return vim.bo.filetype == 'codediff-graph-details'")
        end, "commit details did not get focus")
      end
      hidden(screen, true)
      local pane_win = screen:exec("return vim.api.nvim_get_current_win()")
      local target = screen:exec([[
      local l = package.loaded['codediff.ui.lifecycle']
      local s = l and l.get_session(vim.api.nvim_get_current_tabpage())
      return s and s.modified_win or _G.editor_win
    ]])
      for _ = 1, 3 do
        screen:exec("vim.api.nvim_set_current_win(...)", { pane_win })
        hidden(screen, true)
        local pos = screen:exec("return vim.api.nvim_win_get_position(...)", { pane_win })
        local wheel_seen = screen:exec("return _G.wheel_seen")
        screen:request("nvim_input_mouse", { "wheel", "down", "", 0, pos[1] + 2, pos[2] + 3 })
        h.wait(screen, function()
          return screen:exec(
            [[
          local l = package.loaded['codediff.ui.lifecycle']
          local s = l and l.get_session(vim.api.nvim_get_current_tabpage())
          local r = s and s.refresh
          return _G.wheel_seen > (...) and (not r or not r.loading and not r.running)
        ]],
            { wheel_seen }
          )
        end, "wheel input did not finish before the window switch")
        -- No typed key: WinEnter itself must release any scrolling hide claim.
        lib.eq(
          true,
          screen:exec(
            [[
        local win = ...
        vim.api.nvim_set_current_tabpage(vim.api.nvim_win_get_tabpage(win))
        vim.api.nvim_set_current_win(win)
        return vim.o.guicursor == _G.normal_cursor
      ]],
            { target }
          ),
          pane.name .. " leaked a hidden cursor into the text buffer"
        )
        hidden(screen, false)
        lib.eq(
          screen:exec("return _G.normal_cursor"),
          screen:exec("return vim.o.guicursor"),
          vim.inspect(screen:exec([[
          return {ft=vim.bo.filetype, win=vim.api.nvim_get_current_win(), mouse=vim.fn.getmousepos().winid,
            wheel=require('core.cursor-visibility').active('wheel'), visual=require('core.cursor-visibility').active('visual-scroll')}
        ]]))
        )
      end
      screen:close()
    end
  )
end

lib.test(
  "cursor remains visible in Explorer search and returns after keyboard and mouse pane exits",
  function()
    local screen = editor()
    screen:exec("Snacks.explorer()")
    hidden(screen, true)
    screen:input("/")
    h.wait(screen, function()
      return screen:exec("return vim.bo.filetype == 'snacks_picker_input'")
    end, "search did not open")
    hidden(screen, false)
    screen:input("<Esc><Esc><C-w>l")
    hidden(screen, false)
    screen:exec([[
    local p = Snacks.picker.get({source='explorer'})[1]
    vim.api.nvim_set_current_win(p.list.win.win)
  ]])
    hidden(screen, true)
    local pos = screen:exec("return vim.api.nvim_win_get_position(_G.editor_win)")
    h.click(screen, pos[1] + 5, pos[2] + 10)
    hidden(screen, false)
    screen:close()
  end
)

lib.test(
  "cursor hide reasons cannot restore each other's hidden state or lose custom shapes",
  function()
    local screen = editor()
    screen:exec([[
    local c = require('core.cursor-visibility')
    local win = vim.api.nvim_get_current_win()
    c.hide('first', win)
    c.hide('second', win)
    c.show('first')
    assert(c.hidden())
    c.show('second')
    assert(vim.o.guicursor == _G.normal_cursor)
    vim.o.guicursor = 'n-v-c:block,i-ci-ve:ver30,r-cr:hor20,o:hor50'
    _G.normal_cursor = vim.o.guicursor
    c.hide('first', win)
    vim.o.guicursor = 'n-v-c:block,i-ci-ve:ver35,r-cr:hor20,o:hor50'
    assert(c.hidden(), 'a shape change must not show a cursor over the hidden view')
    vim.api.nvim_exec_autocmds('ColorScheme', {})
    assert(vim.api.nvim_get_hl(0, {name='PaneHiddenCursor'}).blend == 100)
    c.show('first')
    assert(vim.o.guicursor == 'n-v-c:block,i-ci-ve:ver35,r-cr:hor20,o:hor50')
    _G.normal_cursor = vim.o.guicursor
  ]])
    hidden(screen, false)
    screen:close()
  end
)

lib.test(
  "cursor is restored when a wheeled pane closes and when another text tab is entered",
  function()
    local screen = editor()
    screen:exec("Snacks.explorer()")
    hidden(screen, true)
    local pos = screen:exec("return vim.api.nvim_win_get_position(0)")
    screen:request("nvim_input_mouse", { "wheel", "down", "", 0, pos[1] + 2, pos[2] + 3 })
    screen:exec([[
    Snacks.picker.get({source='explorer'})[1]:close()
    vim.api.nvim_set_current_win(_G.editor_win)
  ]])
    hidden(screen, false)
    screen:exec("Snacks.explorer()")
    hidden(screen, true)
    pos = screen:exec("return vim.api.nvim_win_get_position(0)")
    screen:request("nvim_input_mouse", { "wheel", "down", "", 0, pos[1] + 2, pos[2] + 3 })
    screen:exec("vim.cmd('tabnew')")
    hidden(screen, false)
    lib.eq(true, screen:exec("return vim.o.guicursor == _G.normal_cursor"))
    screen:close()
  end
)

lib.test("cursor stays visible while a sidebar is rendered in an unfocused window", function()
  local screen = editor()
  screen:exec([[
    vim.cmd('vnew')
    local sidebar = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(_G.editor_win)
    vim.api.nvim_win_call(sidebar, function()
      vim.bo.filetype = 'snacks_picker_list'
      assert(vim.o.guicursor == _G.normal_cursor, 'background FileType hid the editor cursor')
    end)
    assert(vim.o.guicursor == _G.normal_cursor)
    vim.api.nvim_set_current_win(sidebar)
    assert(require('core.cursor-visibility').hidden())
    vim.api.nvim_win_close(sidebar, true)
    assert(vim.o.guicursor == _G.normal_cursor)
  ]])
  hidden(screen, false)
  screen:close()
end)

lib.test(
  "cursor is restored when leaving a visually scrolled buffer without a keyboard event",
  function()
    local screen = editor()
    screen:input("10GV")
    local pos = screen:exec("return vim.api.nvim_win_get_position(0)")
    screen:request("nvim_input_mouse", { "wheel", "down", "", 0, pos[1] + 5, pos[2] + 10 })
    h.wait(screen, function()
      return screen:exec("return require('core.cursor-visibility').active('visual-scroll')")
    end, "visual wheel did not freeze the cursor")
    screen:exec("vim.cmd('vnew')")
    hidden(screen, false)
    lib.eq(true, screen:exec("return vim.o.guicursor == _G.normal_cursor"))
    screen:close()
  end
)
