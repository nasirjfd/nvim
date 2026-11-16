local lib = require("lib")
local h = require("support")

for _, source in ipairs({ "grep", "files", "lsp_workspace_symbols" }) do
  lib.test("picker wheel keeps selection and preview in sync: " .. source, function()
    local dir = h.tmpdir()
    h.write(dir .. "/first.lua", { "local first_shipping_option_cargo_ready_date = 1" })
    h.write(dir .. "/second.lua", { "local first_shipping_option_cargo_ready_date = 2" })
    local screen = h.nvim(dir)
    screen:exec(
      [[
      local source = ...
      vim.cmd.edit('first.lua')
      if source == 'lsp_workspace_symbols' then
        local cwd = vim.fn.getcwd()
        require('core.symbol-files').clients = function()
          return {{id=1, root_dir=vim.fn.getcwd(), offset_encoding='utf-16', supports_method=function() return true end}}
        end
        require('snacks.picker.source.lsp').request = function(_, _, params, cb)
          local results = {}
          for i, file in ipairs({'first.lua', 'second.lua'}) do
            results[i] = {name = 'Symbol' .. i, kind = 12, location = {
              uri = vim.uri_from_fname(cwd .. '/' .. file),
              range = {start = {line = 0, character = 0}, ['end'] = {line = 0, character = 1}},
            }}
          end
          cb({offset_encoding = 'utf-16'}, results, params())
        end
      end
      if source ~= 'grep' then Snacks.picker[source]() end
    ]],
      { source }
    )
    if source == "grep" then
      screen:exec([[
        vim.fn.search('first_shipping_option_cargo_ready_date')
        vim.cmd('normal! viw')
      ]])
      screen:input("<Space>/")
    end
    h.wait(screen, function()
      return screen:exec(
        [[
        local p = Snacks.picker.get({source = ...})[1]
        return p and not p.finder:running() and p.list:count() == 2
      ]],
        { source }
      )
    end, function()
      return "picker did not populate: "
        .. vim.inspect(screen:exec(
          [[
      local p = Snacks.picker.get({source = ...})[1]
      return {count=p and p.list:count(), notifications=Snacks.notifier.get_history()}
    ]],
          { source }
        ))
    end)
    screen:exec("_G.navigation_picker = Snacks.picker.get({source = ...})[1]", { source })

    local function expect(index)
      h.wait(screen, function()
        return screen:exec(
          [[
          local p, index = _G.navigation_picker, ...
          local item = p.list:get(index)
          if p.list.cursor ~= index or p:current() ~= item or not p.preview.win:valid() then return false end
          local path = Snacks.picker.util.path(item)
          local lines = vim.api.nvim_buf_get_lines(p.preview.win.buf, 0, -1, false)
          return vim.deep_equal(lines, vim.fn.readfile(path))
        ]],
          { index }
        )
      end, function()
        return "wheel cursor, selected item and preview diverged: "
          .. vim.inspect(screen:exec(
            [[
          local p = _G.navigation_picker
          return {cursor=p.list.cursor, expected=..., current=p:current(), top=p.list.top,
            mode=vim.fn.mode(), wheel=require('core.cursor-visibility').active('wheel')}
        ]],
            { index }
          ))
      end)
    end

    expect(1)
    local pos =
      screen:exec("return vim.api.nvim_win_get_position(_G.navigation_picker.list.win.win)")
    -- Wheel over the list while the search field retains focus, then while the list has focus.
    for _, focus in ipairs({ "input", "list" }) do
      screen:exec("_G.navigation_picker:focus(...)", { focus })
      for _, step in ipairs({ { "down", 2 }, { "up", 1 }, { "down", 2 }, { "up", 1 } }) do
        screen:request("nvim_input_mouse", { "wheel", step[1], "", 0, pos[1] + 1, pos[2] + 3 })
        expect(step[2])
      end
    end
    screen:input("<Down>")
    expect(2)
    h.click(screen, pos[1] + 1, pos[2] + 4)
    expect(1)
    local path = screen:exec("return Snacks.picker.util.path(_G.navigation_picker:current())")
    screen:input("<CR>")
    h.wait(screen, function()
      return screen:exec("return vim.api.nvim_buf_get_name(0)") == path
    end, "confirm opened a different item")
    screen:close()
  end)
end
