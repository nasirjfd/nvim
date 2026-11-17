local lib = require("lib")
local h = require("support")

lib.test("file search highlights filename matches instead of competing folder matches", function()
  local dir = h.repo({
    ["src/MessageStoreProjectors/OrderShipmentParcelRouteProjector.php"] = { "example" },
    ["src/PaymentHandlers/UpdatePaymentHandler.lua"] = { "example" },
    ["src/UserSettings/UserSettings.json"] = { "example" },
    ["src/plain/CapacityShadowProjector.php"] = { "example" },
  })
  local screen = h.nvim(dir)
  screen:input("<D-S-o>")
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({source='files'}) == 1")
  end, "file search did not open")
  for _, case in ipairs({
    { query = "projector", name = "OrderShipmentParcelRouteProjector.php", match = "Projector" },
    { query = "handler", name = "UpdatePaymentHandler.lua", match = "Handler" },
    { query = "usersettings.json", name = "UserSettings.json", match = "UserSettings.json" },
    { query = "uph", name = "UpdatePaymentHandler.lua", match = "UpH" },
  }) do
    screen:exec(
      [[
      local p = Snacks.picker.get({source='files'})[1]
      local q = ...; p.input:set(q, ''); p:find()
    ]],
      { case.query }
    )
    h.wait(screen, function()
      return screen:exec([[
        local p = Snacks.picker.get({source='files'})[1]
        return not p.finder:running() and not p.matcher:running() and p:count() > 0
      ]])
    end, function()
      return "filename query did not settle: "
        .. case.query
        .. " "
        .. screen:exec("return vim.fn.execute('messages')")
    end)
    -- Exercise selected and unselected rows: the match foreground must survive CursorLine too.
    for _, selected in ipairs({ true, false }) do
      screen:exec(
        [[
        local name, selected = ...
        local p = Snacks.picker.get({source='files'})[1]
        for i = 1, p.list:count() do
          if vim.fs.basename(p.list:get(i).file) == name then
            p.list:move(selected and i or (i == 1 and 2 or 1), true)
            p:update({force=true})
            return
          end
        end
        error('expected filename not found')
      ]],
        { case.name, selected }
      )
      local row, col = h.find_on_screen(screen, case.name)
      lib.ok(row, "filename was not rendered: " .. case.name)
      local fg =
        screen:exec("return vim.api.nvim_get_hl(0, {name='SnacksPickerMatch', link=false}).fg")
      local expected = case.match
      local at = 1
      local start = case.name:find(expected, 1, true)
      for i = 1, #case.name do
        if (not start or i >= start) and case.name:sub(i, i) == expected:sub(at, at) then
          local cell = screen.grid[row][col + i - 1]
          lib.eq(
            fg,
            screen.highlights[cell[2]].foreground,
            "missing filename match highlight: " .. case.name .. " at " .. i
          )
          at = at + 1
          if at > #expected then
            break
          end
        end
      end
      lib.eq(#expected + 1, at, "did not check the entire match")
    end
  end
  screen:close()
end)

lib.test("filename highlights preserve native behavior for path and advanced queries", function()
  local screen = h.nvim(h.tmpdir())
  lib.ok(
    screen:exec([[
    local Matcher = require('snacks.picker.core.matcher')
    local native = Matcher.new({smartcase=false})
    local filename = Matcher.new({smartcase=false})
    require('core.file-match').attach_highlights(filename)
    for _, case in ipairs({
      {pattern='src/handlers', text='Update.lua src/handlers', file='src/handlers/Update.lua'},
      {pattern="'Handler", text='UpdateHandler.lua src/Handlers', file='src/Handlers/UpdateHandler.lua'},
      {pattern='!missing', text='UpdateHandler.lua src/Handlers', file='src/Handlers/UpdateHandler.lua'},
      {pattern='file:Handler', text='UpdateHandler.lua src/Handlers', file='src/Handlers/UpdateHandler.lua'},
      {pattern='handler', text='Update…lua src/Handlers', file='src/Handlers/UpdateHandler.lua'},
      {pattern='handler', text='Handler: plain non-file result'},
    }) do
      native:init(case.pattern); filename:init(case.pattern)
      local item = {text=case.text, file=case.file, idx=1, score=0}
      assert(vim.deep_equal(native:positions(item), filename:positions(item)), case.pattern)
    end
    native:close(); filename:close()
    return true
  ]]),
    "fallback highlighting changed"
  )
  screen:close()
end)
