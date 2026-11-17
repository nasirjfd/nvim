local lib = require("lib")
local h = require("support")

lib.test(
  "code action ordering preserves original callback indices and leaves other menus unchanged",
  function()
    local screen = h.nvim(h.tmpdir())
    for _, kind in ipairs({ "codeaction", "unrelated" }) do
      screen:exec(
        [[
      _G.action_choice = nil
      local items = {
        {title='Add JSDoc'},
        {title='Extract function'},
        {title='Import Doc'},
        {title='Add use statement for Documentation'},
        {title='Add missing imports'},
      }
      for i, item in ipairs(items) do items[i] = {action=item, ctx={client_id=-1}} end
      vim.ui.select(items, {kind=..., format_item=function(item) return item.action.title end}, function(item, index)
        _G.action_choice = {title=item and item.action.title or 'cancelled', index=index or 0}
      end)
    ]],
        { kind }
      )
      h.wait(screen, function()
        return screen:exec([[
        local p = Snacks.picker.get({source='select'})[1]
        return p and p:count() == 5 and not p.matcher:running()
      ]])
      end, "selection menu did not open")
      local expected = kind == "codeaction" and "Import Doc" or "Add JSDoc"
      if kind == "codeaction" then
        lib.eq(
          {
            "Import Doc",
            "Add use statement for Documentation",
            "Add missing imports",
            "Extract function",
            "Add JSDoc",
          },
          screen:exec([[
          local p = Snacks.picker.get({source='select'})[1]
          local out = {}
          for i = 1, p.list:count() do out[i] = p.list:get(i).item.action.title end
          return out
        ]]),
          "imports named Doc/Documentation were treated as documentation actions"
        )
      end
      lib.eq(
        expected,
        screen:exec([[
        return Snacks.picker.get({source='select'})[1].list:get(1).item.action.title
    ]]),
        "wrong first menu item"
      )
      lib.ok(
        screen:exec([[
      return Snacks.picker.get({source='select'})[1].list:get(1).text:match('^1 ') ~= nil
    ]]),
        "first displayed item retained its old number"
      )
      screen:input("<CR>")
      h.wait(screen, function()
        return screen:exec("return _G.action_choice ~= nil")
      end, "selection callback was lost")
      lib.eq(
        { title = expected, index = kind == "codeaction" and 3 or 1 },
        screen:exec("return _G.action_choice"),
        "selection callback lost the original item or index"
      )
    end
    screen:close()
  end
)
