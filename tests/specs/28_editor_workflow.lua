local lib = require("lib")
local h = require("support")

lib.test("rename shortcuts invoke LSP rename in the original editor", function()
  local dir = h.tmpdir()
  h.write(dir .. "/rename.txt", { "symbol" })
  local screen = h.nvim(dir)
  screen:exec([[
    vim.cmd('edit rename.txt')
    _G.rename_calls = 0
    _G.rename_buf = vim.api.nvim_get_current_buf()
    vim.lsp.buf.rename = function()
      assert(vim.api.nvim_get_current_buf() == _G.rename_buf, 'rename ran in the find bar')
      _G.rename_calls = _G.rename_calls + 1
    end
    -- Keymaps normally hold the LSP function directly; install again with the test spy.
    package.loaded['core.gui-keymaps'] = nil
    require('core.gui-keymaps')
  ]])
  for i, key in ipairs({ "<F2>", "<S-F6>", "<F18>", "<D-h>h", "<D-h><D-h>" }) do
    screen:input(key)
    h.wait(screen, function()
      return screen:exec("return _G.rename_calls") == i
    end, "rename shortcut failed: " .. key)
  end
  screen:close()
end)

lib.test("HTTP paste expands JSON including streamed terminal pastes", function()
  local dir = h.tmpdir()
  h.write(
    dir .. "/request.http",
    { "POST https://example.test", "Content-Type: application/json", "", "" }
  )
  local screen = h.nvim(dir)
  screen:exec([[vim.cmd('edit request.http'); vim.api.nvim_win_set_cursor(0, {4, 0})]])
  screen:input("i")
  screen:exec([[vim.api.nvim_paste('{"hello":', true, 1); vim.api.nvim_paste('[1,2]}', true, 3)]])
  lib.eq({
    "POST https://example.test",
    "Content-Type: application/json",
    "",
    "{",
    '  "hello": [',
    "    1,",
    "    2",
    "  ]",
    "}",
  }, screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
  screen:close()
end)

lib.test("selection formatting uses the full selected lines and preserves HTTP headers", function()
  local dir = h.tmpdir()
  h.write(
    dir .. "/request.http",
    { "POST https://example.test", "", '{"hello":[1,2]}', "### Next", "GET https://example.test" }
  )
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit request.http'); vim.api.nvim_win_set_cursor(0, {3, 0})")
  screen:input("V<Space>cf")
  h.wait(screen, function()
    return screen:exec([[return vim.api.nvim_buf_get_lines(0, 2, 3, false)[1] == '{']])
  end, "selected JSON did not format")
  lib.eq("### Next", screen:exec("return vim.api.nvim_buf_get_lines(0, -3, -2, false)[1]"))
  lib.eq(
    "POST https://example.test",
    screen:exec("return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]")
  )
  screen:close()
end)

lib.test("filename returns immediately after executed commands and Escape", function()
  local dir = h.tmpdir()
  h.write(dir .. "/visible.txt", { "hello" })
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit visible.txt')")
  local function visible()
    return screen:exec([[
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local c = vim.api.nvim_win_get_config(win)
        local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
        if c.relative == 'editor' and c.zindex == 250 and not c.hide and lines[1]:find('visible.txt', 1, true) then return true end
      end
      return false
    ]])
  end
  h.wait(screen, visible, "filename not visible")
  screen:input(":")
  h.wait(screen, function()
    return not visible()
  end, "filename covers command line")
  screen:input("let g:filename_test = 1<CR>")
  h.wait(screen, visible, "filename did not return after a command")
  screen:input(":<Esc>")
  h.wait(screen, visible, "filename did not return after Escape")
  screen:exec(
    "vim.cmd('vnew'); vim.bo.buftype = 'nofile'; vim.api.nvim_exec_autocmds('BufEnter', {})"
  )
  h.wait(screen, visible, "focusing a pane lost the editor filename")
  screen:close()
end)

lib.test(
  "Git F4 return point preserves a whole commit diff across backward and forward jumps",
  function()
    local lines = { "one", "two", "three", "four", "five", "six", "seven", "eight" }
    local dir = h.repo({ ["a.txt"] = lines, ["b.txt"] = { "two" } })
    lines[7] = "changed"
    h.write(dir .. "/a.txt", lines)
    h.write(dir .. "/b.txt", { "also changed" })
    h.git(dir, "commit", "-qam", "change")
    local screen = h.nvim(dir)
    screen:exec("vim.cmd('edit b.txt'); vim.cmd('CodeDiff graph')")
    h.wait(screen, function()
      return screen:exec(
        [[local g = require('codediff.ui.graph').get(vim.api.nvim_get_current_tabpage()); return g and g.details and next(g.details.files or {}) ~= nil]]
      )
    end, "graph not ready")
    local graph_state = screen:exec(
      "return {vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf(), #vim.api.nvim_tabpage_list_wins(0)}"
    )
    screen:input("<C-o><C-i>")
    lib.eq(
      graph_state,
      screen:exec(
        "return {vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf(), #vim.api.nvim_tabpage_list_wins(0)}"
      ),
      "jump keys changed the graph"
    )
    screen:input("<CR><CR>")
    h.wait(screen, function()
      return screen:exec(
        [[local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage()); return s and s.original_bufnr and vim.api.nvim_buf_is_valid(s.original_bufnr)]]
      )
    end, "commit diff not ready")
    h.wait(screen, function()
      return screen:exec(
        [[local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage()); return s and s.refresh and not s.refresh.loading and not s.refresh.running]]
      )
    end, "commit diff did not settle")
    screen:exec([[
    _G.workflow_tab = vim.api.nvim_get_current_tabpage()
    _G.workflow_session = require('codediff.ui.lifecycle').get_session(_G.workflow_tab)
    _G.workflow_win = vim.api.nvim_get_current_win()
  ]])
    lib.ok(
      screen:exec("return _G.workflow_win == _G.workflow_session.modified_win"),
      "commit page did not focus the modified diff pane"
    )
    lib.eq(
      7,
      screen:exec("return vim.api.nvim_win_get_cursor(0)[1]"),
      "commit page did not start at the first change of the first file"
    )
    h.wait(screen, function()
      return screen:exec([[
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local c = vim.api.nvim_win_get_config(win)
          if c.relative == 'editor' and c.zindex == 250 and not c.hide then
            local text = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1]
            return text:find('a.txt', 1, true) ~= nil and not text:find('codediff:', 1, true)
          end
        end
        return false
      ]])
    end, "diff filename is missing or shows a virtual URL")
    screen:input("<C-o><C-i>")
    lib.ok(
      screen:exec("return vim.api.nvim_get_current_win() == _G.workflow_win"),
      "native jumps changed a diff pane"
    )
    screen:exec(
      "_G.workflow_notifications = {}; vim.notify = function(msg) table.insert(_G.workflow_notifications, msg) end"
    )
    screen:input("<F4>")
    h.wait(screen, function()
      return screen:exec(
        "return vim.api.nvim_get_current_tabpage() ~= _G.workflow_tab and vim.fn.expand('%:t') == 'a.txt'"
      )
    end, function()
      return "F4 did not open the working file: "
        .. vim.inspect(screen:exec([[
      return {tab=vim.api.nvim_get_current_tabpage(), ft=vim.bo.filetype, name=vim.api.nvim_buf_get_name(0),
        map=vim.inspect(vim.fn.maparg('<F4>', 'n', false, true)), messages=_G.workflow_notifications,
        paths={require('codediff.ui.lifecycle').get_paths(_G.workflow_tab)}}
    ]]))
    end)
    lib.eq(
      7,
      screen:exec("return vim.api.nvim_win_get_cursor(0)[1]"),
      "F4 did not open the working file at the first change"
    )
    screen:exec("vim.cmd('edit b.txt')")
    screen:input("<C-o>")
    h.wait(screen, function()
      return screen:exec("return vim.fn.expand('%:t') == 'a.txt'")
    end, "first jump did not return to a.txt")
    screen:input("<C-o>")
    h.wait(screen, function()
      return screen:exec("return vim.api.nvim_get_current_win() == _G.workflow_win")
    end, "second jump did not return to the complete diff")
    lib.ok(
      screen:exec(
        [[return require('codediff.ui.lifecycle').get_session(_G.workflow_tab) == _G.workflow_session and vim.api.nvim_win_is_valid(_G.workflow_session.original_win)]]
      ),
      "diff was destroyed"
    )
    screen:input("<C-,>")
    h.wait(screen, function()
      return screen:exec(
        "return vim.fn.expand('%:t') == 'a.txt' and vim.api.nvim_get_current_tabpage() ~= _G.workflow_tab"
      )
    end, "first forward jump did not return to the editor")
    screen:input("<C-,>")
    h.wait(screen, function()
      return screen:exec("return vim.fn.expand('%:t') == 'b.txt'")
    end, "forward jumps did not restore b.txt")
    screen:close()
  end
)
