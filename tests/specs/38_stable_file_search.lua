local lib = require("lib")
local h = require("support")

lib.test("file search publishes complete rankings while typing shipment", function()
  local dir = h.repo({ ["Shipment.php"] = { "<?php" } })
  local screen = h.nvim(dir)
  screen:input("<Space><Space>")
  h.wait(screen, function()
    return screen:exec([[
      local p = Snacks.picker.get({source='files'})[1]
      return p and p.shown and not p.finder:running() and not p.matcher:running()
    ]])
  end, "file picker did not open")
  screen:exec([[
    local p = Snacks.picker.get({source='files'})[1]
    -- Force several async frames even on a fast machine, without thousands of disk files.
    p.finder._find = function()
      local items = {}
      for i = 1, 100 do
        local file = ('Shipment%03d.php'):format(i)
        items[i] = {text=file, file=file, cwd=vim.fn.getcwd()}
      end
      return items
    end
    local on_match = p.matcher.opts.on_match
    p.matcher.opts.on_match = function(...)
      on_match(...)
      vim.uv.sleep(1)
    end
    _G.partial_renders = {}
    vim.api.nvim_buf_attach(p.list.win.buf, false, {on_lines=function()
      if p.matcher:running() or p.finder:running() then
        table.insert(_G.partial_renders, p.matcher.pattern)
      end
    end})
    p:find()
  ]])
  local function settled(pattern, count)
    h.wait(screen, function()
      return screen:exec(
        [[
        local pattern, count = ...
        local p = Snacks.picker.get({source='files'})[1]
        return p.matcher.pattern == pattern and not p.matcher:running()
          and not p.finder:running() and p.list:count() == count
          and #p.list.visible == math.min(count, p.list.state.height)
      ]],
        { pattern, count }
      )
    end, function()
      return "file results did not settle for "
        .. pattern
        .. vim.inspect(screen:exec([[
        local p = Snacks.picker.get({source='files'})[1]
        return {pattern=p.matcher.pattern, matching=p.matcher:running(), finding=p.finder:running(),
          count=p.list:count(), visible=#p.list.visible, height=p.list.state.height}
      ]]))
    end)
  end
  settled("", 100)
  local pattern = ""
  for char in ("shipment"):gmatch(".") do
    pattern = pattern .. char
    screen:input(char)
    settled(pattern, 100)
  end
  screen:input("zzzz")
  settled("shipmentzzzz", 0)
  screen:input(string.rep("<BS>", 12))
  settled("", 100)
  screen:input("shipment")
  settled("shipment", 100)
  screen:input("<Down>")
  lib.ok(
    screen:exec([[
    local p = Snacks.picker.get({source='files'})[1]
    return p.list.cursor == 2
  ]]),
    "navigation stopped working after matching"
  )
  lib.eq({}, screen:exec("return _G.partial_renders"), "intermediate rankings reached the screen")
  screen:close()
end)
