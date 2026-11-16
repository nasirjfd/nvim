local lib = require("lib")
local h = require("support")

local function editor()
  local dir = h.repo({ ["Projector.lua"] = { "local projector = true", "second", "third" } })
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit Projector.lua')")
  return screen
end

lib.test(
  "Persian keyboard normal shortcuts work while ordinary inserted Persian stays unchanged",
  function()
    local screen = editor()
    screen:input("تت") -- physical j j
    lib.eq(3, screen:exec("return vim.api.nvim_win_get_cursor(0)[1]"))
    screen:input("نن") -- physical k k
    lib.eq(1, screen:exec("return vim.api.nvim_win_get_cursor(0)[1]"))
    screen:input("شسلام فارسی<Esc>") -- physical a enters Insert; subsequent Persian is actual text
    lib.ok(
      screen:exec(
        "return vim.api.nvim_get_current_line():find('سلام فارسی', 1, true) ~= nil"
      ),
      "inserted Persian was translated"
    )
    screen:close()
  end
)

lib.test("Persian keyboard Cmd+Shift+O invokes file search using the English shortcut", function()
  local screen = editor()
  screen:input("<D-S-خ>") -- physical Cmd+Shift+O
  h.wait(screen, function()
    return screen:exec(
      "return #Snacks.picker.get({source='files'}) == 1 and vim.bo.filetype == 'snacks_picker_input'"
    )
  end, "Persian-layout Cmd+Shift+O did not open Files")
  screen:input("حقختثزفخق") -- projector in the Persian layout
  lib.eq(
    "حقختثزفخق",
    screen:exec("return vim.api.nvim_get_current_line()"),
    "search conversion must be opt-in"
  )
  screen:input("<C-S-l>")
  h.wait(screen, function()
    return screen:exec(
      "return vim.api.nvim_get_current_line() == 'projector' and vim.g.persian_search_english == true"
    )
  end, "search toggle did not convert the existing query")
  h.wait(screen, function()
    return screen:exec([[
      local p=Snacks.picker.get({source='files'})[1]
      return p and p.list:count()==1 and p.list:get(1).file:find('Projector.lua',1,true) ~= nil
    ]])
  end, "translated query did not find the English filename")
  screen:close()
end)

lib.test(
  "Persian search conversion is optional in file and find bars and never changes commit text",
  function()
    local screen = editor()
    screen:exec("vim.cmd('PersianSearch on')")
    screen:input("<D-ب>") -- physical Cmd+F
    h.wait(screen, function()
      return screen:exec("return vim.bo.filetype=='findbar' and vim.b.persian_search_keys == true")
    end, "Persian-layout Cmd+F did not open Find")
    screen:input("حقختثزفخق")
    h.wait(screen, function()
      return screen:exec("return vim.api.nvim_get_current_line()=='projector'")
    end, "find bar did not translate Persian-layout typing")
    screen:input("<Esc>")
    screen:input("<D-f>")
    h.wait(screen, function()
      return screen:exec("return vim.bo.filetype=='findbar' and vim.fn.mode()=='s'")
    end, "reopened search did not select its old query")
    screen:input("حقختثزفخق")
    h.wait(screen, function()
      return screen:exec(
        "return vim.api.nvim_get_current_line()=='projector' and vim.fn.mode()=='i'"
      )
    end, "Persian-layout typing did not replace the selected search correctly")
    screen:input("<Esc>")
    screen:exec("vim.ui.input({prompt='Commit summary: '}, function() end)")
    h.wait(screen, function()
      return screen:exec("return vim.bo.filetype=='snacks_input' and vim.fn.mode()=='i'")
    end, "commit-style prompt did not open")
    screen:input("سلام فارسی")
    lib.eq(
      "سلام فارسی",
      screen:exec("return vim.api.nvim_get_current_line()"),
      "commit message Persian was translated"
    )
    screen:exec("vim.cmd('PersianSearch off'); vim.cmd('PersianSearch off')")
    lib.eq(
      false,
      screen:exec("return vim.g.persian_search_english"),
      "off must disable, not toggle conversion"
    )
    screen:close()
  end
)

lib.test("Persian-layout symbol search sends English queries when conversion is enabled", function()
  local screen = editor()
  screen:exec([[
    vim.cmd('PersianSearch on')
    local symbol_file = vim.api.nvim_buf_get_name(0)
    require('snacks.picker.source.lsp').request = function(_, _, params, cb)
      local request = params()
      _G.persian_symbol_query = request.query
      cb({offset_encoding='utf-16'}, {{
        name='Projector', kind=12,
        location={uri=vim.uri_from_fname(symbol_file), range={
          start={line=0, character=0}, ['end']={line=0, character=1}
        }}
      }}, request)
    end
    Snacks.picker.lsp_workspace_symbols()
  ]])
  h.wait(screen, function()
    return screen:exec(
      "return vim.bo.filetype=='snacks_picker_input' and vim.b.persian_search_keys==true"
    )
  end, "symbol search input did not attach")
  screen:input("حقختثزفخق")
  h.wait(screen, function()
    return screen:exec([[
      local p=Snacks.picker.get({source='lsp_workspace_symbols'})[1]
      return _G.persian_symbol_query=='projector' and p and p.list:count()==1
    ]])
  end, function()
    return "symbol search did not receive translated query: "
      .. vim.inspect(screen:exec([[
      local p=Snacks.picker.get({source='lsp_workspace_symbols'})[1]
      return {query=_G.persian_symbol_query, text=vim.api.nvim_get_current_line(),
        count=p and p.list:count(), live=p and p.opts.live}
    ]]))
  end)
  screen:close()
end)

lib.test(
  "Persian keyboard supports multi-key and Insert-mode modified shortcuts without changing text",
  function()
    local screen = editor()
    screen:exec([[
    _G.persian_shortcuts = 0
    vim.cmd('PersianSearch on')
    vim.keymap.set('n', '<Space>xy', function() _G.persian_shortcuts=_G.persian_shortcuts+1 end)
    vim.keymap.set('i', '<D-x>', function() _G.persian_shortcuts=_G.persian_shortcuts+1 end, {buffer=true})
    require('core.persian-keyboard').shortcuts()
    require('core.persian-keyboard').shortcuts(vim.api.nvim_get_current_buf())
  ]])
    screen:input("<Space>طغ")
    lib.eq(
      1,
      screen:exec("return _G.persian_shortcuts"),
      "normal multi-key shortcut was not translated"
    )
    screen:input("iسلام<D-ط> فارسی<Esc>")
    lib.eq(
      2,
      screen:exec("return _G.persian_shortcuts"),
      "modified shortcut did not work while typing Persian"
    )
    lib.ok(
      screen:exec("return vim.api.nvim_get_current_line():find('سلام فارسی',1,true)~=nil"),
      "normal text was changed"
    )
    screen:close()
  end
)
