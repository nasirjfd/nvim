local lib = require("lib")
local h = require("support")

-- A real Neovim LSP client with an in-process protocol peer: no installed server,
-- project mutation or network is needed to exercise requests and workspace edits.
local function editor()
  local screen = h.nvim(h.tmpdir())
  screen:exec([[
    vim.cmd.enew()
    vim.api.nvim_buf_set_name(0, vim.fn.getcwd() .. '/shortcuts.txt')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {'WidgetService', 'AnotherService'})
    _G.shortcut_requests = {}
    _G.shortcut_client = vim.lsp.start({
      name = 'shortcut-test', root_dir = vim.fn.getcwd(),
      cmd = function(dispatchers)
        local closing, id = false, 0
        return {
          request = function(method, params, callback)
            id = id + 1
            local result
            if method == 'initialize' then
              result = {capabilities = {codeActionProvider=true, completionProvider={triggerCharacters={'>','.',':'}}}}
            elseif method == 'textDocument/codeAction' then
              _G.shortcut_requests[#_G.shortcut_requests+1] = params
              result = {{title='Import WidgetService', kind='quickfix', edit={changes={
                [params.textDocument.uri] = {{range={start={line=0,character=0},
                  ['end']={line=0,character=0}}, newText='use Example.WidgetService;\n'}}
              }}}}
              if _G.shortcut_mixed_actions then
                local import = result[1]
                import.title = 'use Example.WidgetService'
                result = {
                  {title='Add PHPDoc for WidgetService', kind='refactor.rewrite'},
                  {title='Rename symbol', kind='refactor.rename'},
                  import,
                  {title='Generate docstring', kind='refactor.rewrite'},
                  {title='Resolve missing types', kind='source.addMissingImports'},
                  {title='Extract method', kind='refactor.extract'},
                }
              end
            elseif method == 'textDocument/completion' then
              _G.shortcut_completions = (_G.shortcut_completions or 0) + 1
              result = {{label='WidgetService', kind=7, insertText='WidgetService'}}
            end
            vim.schedule(function() callback(nil, result) end)
            return true, id
          end,
          notify = function() return true end,
          is_closing = function() return closing end,
          terminate = function() closing=true; dispatchers.on_exit(0, 0) end,
        }
      end,
    })
  ]])
  h.wait(screen, function()
    return screen:exec(
      "return vim.fn.maparg('<D-.>', 'n', false, true).desc == 'Code Action / Quick Fix'"
    )
  end, "LSP shortcut did not attach")
  return screen
end

lib.test(
  "LSP completion automatically follows inserted trigger characters without re-entering insert",
  function()
    local screen = editor()
    for _, input in ipairs({ "typed", "buffered" }) do
      for _, trigger in ipairs({ "->", ".", "::" }) do
        screen:exec("vim.api.nvim_buf_set_lines(0, 0, -1, false, {'object'})")
        screen:input("A")
        screen:exec("require('blink.cmp').hide()")
        if input == "typed" then
          screen:input(trigger)
        else
          screen:exec("vim.api.nvim_paste(..., false, -1)", { trigger })
        end
        h.wait(screen, function()
          return screen:exec("return require('blink.cmp').is_visible() and vim.fn.mode() == 'i'")
        end, "LSP menu did not open after inserted " .. trigger)
        screen:input("<Esc>")
      end
    end
    screen:close()
  end
)

for _, mode in ipairs({ "normal", "visual", "insert" }) do
  lib.test("Cmd+. requests and applies an LSP import quick fix in " .. mode .. " mode", function()
    local screen = editor()
    if mode == "visual" then
      screen:input("Vj")
    elseif mode == "insert" then
      screen:input("A")
    end
    screen:input("<D-.>")
    h.wait(screen, function()
      return screen:exec([[
        local p = Snacks.picker.get({source='select'})[1]
        return p and p:count() == 1
      ]])
    end, "Cmd+. did not offer the server's quick fix")
    lib.eq(1, screen:exec("return #_G.shortcut_requests"), "code action requested more than once")
    if mode == "visual" then
      lib.eq(
        { 0, 1 },
        screen:exec([[
        local range = _G.shortcut_requests[1].range
        return {range.start.line, range['end'].line}
      ]]),
        "code action lost the selected range"
      )
    end
    screen:input("<CR>")
    h.wait(screen, function()
      return screen:exec(
        "return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'use Example.WidgetService;'"
      )
    end, "selected quick fix did not apply its import edit")
    screen:close()
  end)
end

for _, key in ipairs({ "<D-.>", "<Space>ca" }) do
  lib.test("code actions put imports first and documentation last via " .. key, function()
    local screen = editor()
    screen:exec("_G.shortcut_mixed_actions = true")
    screen:input(key)
    h.wait(screen, function()
      return screen:exec([[
        local p = Snacks.picker.get({source='select'})[1]
        return p and p:count() == 6 and not p.matcher:running()
      ]])
    end, "code action menu did not open")
    lib.eq(
      {
        "use Example.WidgetService",
        "Resolve missing types",
        "Rename symbol",
        "Extract method",
        "Add PHPDoc for WidgetService",
        "Generate docstring",
      },
      screen:exec([[
      local p = Snacks.picker.get({source='select'})[1]
      local titles = {}
      for i = 1, p.list:count() do titles[i] = p.list:get(i).item.action.title end
      return titles
    ]]),
      "code actions did not keep stable import/other/documentation groups"
    )
    screen:input("<CR>")
    h.wait(screen, function()
      return screen:exec(
        "return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'use Example.WidgetService;'"
      )
    end, "first action no longer applies the import edit")
    screen:close()
  end)
end

lib.test(
  "Cmd+I manually opens existing LSP completion without accepting or inserting Tab",
  function()
    local screen = editor()
    screen:exec([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {'Wid'})
    require('blink.cmp.config').completion.menu.auto_show = false
  ]])
    screen:input("A")
    screen:exec("require('blink.cmp').hide()")
    screen:input("<D-i>")
    h.wait(screen, function()
      return screen:exec([[
      local cmp = require('blink.cmp')
      if not cmp.is_visible() then return false end
      for _, item in ipairs(cmp.get_items()) do
        if item.label == 'WidgetService' then return true end
      end
      return false
    ]])
    end, "Cmd+I did not show the existing completion menu")
    lib.eq(
      "Wid",
      screen:exec("return vim.api.nvim_get_current_line()"),
      "Cmd+I inserted a tab or accepted completion"
    )
    lib.eq("i", screen:exec("return vim.fn.mode()"), "Cmd+I left insert mode")
    lib.ok(screen:exec("return (_G.shortcut_completions or 0) > 0"), "completion bypassed the LSP")
    screen:close()
  end
)

lib.test(
  "coding shortcuts preserve ordinary Enter/Tab and existing pane Ctrl+Enter actions",
  function()
    local screen = editor()
    lib.ok(
      screen:exec([[
    return vim.fn.maparg('<CR>', 'n') == '' and vim.fn.maparg('<D-i>', 'n') == ''
      and vim.fn.maparg('<C-CR>', 'n') == '' and vim.fn.maparg('<C-CR>', 'i') == ''
      and vim.fn.keytrans(vim.keycode('<D-i>')) ~= vim.fn.keytrans(vim.keycode('<Tab>'))
      and vim.fn.keytrans(vim.keycode('<C-CR>')) ~= vim.fn.keytrans(vim.keycode('<CR>'))
  ]]),
      "modified keys collided with ordinary keys"
    )
    for _, pane in ipairs({
      { "modules.http_requests", "http_run" },
      { "modules.phpunit.pane", "tests_run" },
    }) do
      screen:exec("require(...).toggle()", { pane[1] })
      h.wait(screen, function()
        return screen:exec(
          [[
        local module, action = ...
        local p = require(module).panes()[1]
        return p and p.opts.win.list.keys['<C-CR>'] == action
          and vim.fn.maparg('<C-CR>', 'n', false, true).buffer == 1
      ]],
          pane
        )
      end, "pane Ctrl+Enter binding changed: " .. pane[1])
    end
    screen:close()
  end
)
