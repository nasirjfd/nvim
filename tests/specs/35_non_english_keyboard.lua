local lib = require("lib")
local h = require("support")

local function editor()
  local dir = h.repo({ ["Projector.lua"] = { "local projector = true", "second", "third" } })
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit Projector.lua')")
  return screen
end

local function alerts(screen)
  return screen:exec([[
    local found={}
    for _,win in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype=='non_english_keyboard_alert' then
        found[#found+1]=win
      end
    end
    return found
  ]])
end

lib.test(
  "Non-English motion alert is top-right, never stacks and expires after the last key",
  function()
    local screen = editor()
    local editor_win = screen:exec("return vim.api.nvim_get_current_win()")
    screen:input("ت")
    h.wait(screen, function()
      return #alerts(screen) == 1
    end, "motion alert did not appear")
    local win = alerts(screen)[1]
    lib.ok(
      screen:exec(([[
    local cfg=vim.api.nvim_win_get_config(%d)
    return cfg.relative=='editor' and cfg.row==0 and not cfg.focusable
      and cfg.col+cfg.width+2==vim.o.columns
  ]]):format(win)),
      "alert is not in the top-right"
    )
    lib.eq(editor_win, screen:exec("return vim.api.nvim_get_current_win()"), "alert stole focus")
    vim.wait(850)
    screen:input("ن")
    vim.wait(850)
    lib.eq({ win }, alerts(screen), "alert stacked or expired before the restarted timeout")
    screen:input("تنتن")
    lib.eq({ win }, alerts(screen), "a burst created another alert")
    h.wait(screen, function()
      return #alerts(screen) == 0
    end, "alert did not expire", 2500)
    screen:input("ت")
    h.wait(screen, function()
      return #alerts(screen) == 1
    end, "alert did not reappear")
    screen:close()
  end
)

lib.test("Non-English search alert appears only for translated input", function()
  local screen = editor()
  screen:input("iسلام<Esc>")
  lib.eq({}, alerts(screen), "ordinary inserted text showed a translation alert")
  screen:input("<D-S-o>")
  h.wait(screen, function()
    return screen:exec(
      "return vim.bo.filetype=='snacks_picker_input' and vim.b.non_english_search_keys"
    )
  end, "file picker did not open")
  screen:input("pro")
  lib.eq({}, alerts(screen), "English input showed a translation alert")
  screen:input("تثزفخق")
  h.wait(screen, function()
    return #alerts(screen) == 1
  end, "search alert did not appear")
  lib.eq("projector", screen:exec("return vim.api.nvim_get_current_line()"))
  screen:close()
end)

lib.test(
  "Non-English keyboard shortcuts work while ordinary inserted text stays unchanged",
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

lib.test(
  "Non-English keyboard Cmd+Shift+O invokes file search using the English shortcut",
  function()
    local screen = editor()
    screen:input("<D-S-خ>") -- physical Cmd+Shift+O
    h.wait(screen, function()
      return screen:exec(
        "return #Snacks.picker.get({source='files'}) == 1 and vim.bo.filetype == 'snacks_picker_input'"
      )
    end, "Persian-layout Cmd+Shift+O did not open Files")
    screen:input("حقختثزفخق") -- projector in the Persian layout
    lib.eq(
      "projector",
      screen:exec("return vim.api.nvim_get_current_line()"),
      "file names must automatically use the English keyboard layout"
    )
    h.wait(screen, function()
      return screen:exec([[
      local p=Snacks.picker.get({source='files'})[1]
      return p and p.list:count()==1 and p.list:get(1).file:find('Projector.lua',1,true) ~= nil
    ]])
    end, "translated query did not find the English filename")
    screen:close()
  end
)

lib.test("Non-English recent-file search translates typing and pasted mixed queries", function()
  local screen = editor()
  screen:exec([[
    vim.cmd('NonEnglishSearch off')
    vim.v.oldfiles = {vim.api.nvim_buf_get_name(0)}
    vim.cmd('enew')
  ]])
  screen:input("<D-e>")
  h.wait(screen, function()
    return screen:exec([[
      local p=Snacks.picker.get({source='recent'})[1]
      return p and vim.bo.filetype=='snacks_picker_input' and vim.b.non_english_search_keys
    ]])
  end, function()
    return "Cmd+E did not open recent files: "
      .. vim.inspect(screen:exec([[
      local ps={}
      for _,p in ipairs(Snacks.picker.get()) do ps[#ps+1]={source=p.opts.source,buf=p.input.win.buf} end
      return {pickers=ps,ft=vim.bo.filetype,keys=vim.b.non_english_search_keys,mode=vim.fn.mode()}
    ]]))
  end)
  screen:input("حقختثزفخق")
  h.wait(screen, function()
    return screen:exec([[
      local p=Snacks.picker.get({source='recent'})[1]
      return vim.api.nvim_get_current_line()=='projector' and p.list:count()==1
    ]])
  end, "recent files did not translate typed Persian")
  screen:exec([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {''})
    vim.api.nvim_win_set_cursor(0, {1, 0})
    vim.api.nvim_paste('حقختثزفخق.lua', false, -1)
  ]])
  h.wait(screen, function()
    return screen:exec([[
      local p=Snacks.picker.get({source='recent'})[1]
      return vim.api.nvim_get_current_line()=='projector.lua' and p.list:count()==1
    ]])
  end, "recent files did not translate a pasted mixed-language query")
  screen:close()
end)

lib.test("Non-English text searches stay unchanged without the optional toggle", function()
  local screen = editor()
  screen:exec("vim.cmd('NonEnglishSearch off'); Snacks.picker.grep()")
  h.wait(screen, function()
    return screen:exec(
      "return vim.bo.filetype=='snacks_picker_input' and vim.b.non_english_search_keys"
    )
  end, "grep did not attach")
  screen:input("سلام")
  lib.eq("سلام", screen:exec("return vim.api.nvim_get_current_line()"))
  screen:close()
end)

lib.test(
  "Non-English search conversion is optional in find bars and never changes commit text",
  function()
    local screen = editor()
    screen:exec("vim.cmd('NonEnglishSearch on')")
    screen:input("<D-ب>") -- physical Cmd+F
    h.wait(screen, function()
      return screen:exec(
        "return vim.bo.filetype=='findbar' and vim.b.non_english_search_keys == true"
      )
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
    screen:exec("vim.cmd('NonEnglishSearch off'); vim.cmd('NonEnglishSearch off')")
    lib.eq(
      false,
      screen:exec("return vim.g.non_english_search"),
      "off must disable, not toggle conversion"
    )
    screen:close()
  end
)

lib.test("Non-English symbol search automatically sends English queries", function()
  local screen = editor()
  screen:exec([[
    vim.cmd('NonEnglishSearch off')
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
      "return vim.bo.filetype=='snacks_picker_input' and vim.b.non_english_search_keys==true"
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
  "Non-English keyboard supports multi-key and Insert-mode modified shortcuts without changing text",
  function()
    local screen = editor()
    screen:exec([[
    _G.persian_shortcuts = 0
    vim.cmd('NonEnglishSearch on')
    vim.keymap.set('n', '<Space>xy', function() _G.persian_shortcuts=_G.persian_shortcuts+1 end)
    vim.keymap.set('i', '<D-x>', function() _G.persian_shortcuts=_G.persian_shortcuts+1 end, {buffer=true})
    require('core.non-english-keyboard').shortcuts()
    require('core.non-english-keyboard').shortcuts(vim.api.nvim_get_current_buf())
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
