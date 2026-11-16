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
  screen:input("s")
  vim.wait(20)
  screen:input("hipment")
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

lib.test("fast file matching keeps fuzzy membership and advanced search syntax", function()
  local screen = h.nvim(h.tmpdir())
  screen:exec([[
    local Matcher = require('snacks.picker.core.matcher')
    local normal = Matcher.new({smartcase=false, ignorecase=true})
    local fast = Matcher.new({smartcase=false, ignorecase=true})
    require('core.file-match').attach(fast)
    local paths = {
      'vendor/shipping/src/Shipment.php',
      'vendor/ParcelProjectionRecord.php',
      'vendor/ScannableCodeLookup.php',
      'vendor/PostPaymentAPIPayload.php',
      'a/' .. string.rep('long/folders/', 40) .. 'b.php',
      'folder/shipping/Other.php',
    }
    for _, query in ipairs({'s','sh','shipment','pprecord','scl','post','ab','SHIPMENT','shipping/other'}) do
      fast:init(query)
      for _, path in ipairs(paths) do
        local at, expected = 0, true
        for char in query:lower():gmatch('.') do
          at = path:lower():find(char, at + 1, true)
          if not at then expected = false; break end
        end
        local item = {file=path, text=path}
        assert((fast:match(item) > 0) == expected, query .. ': ' .. path)
        assert((fast:match(item) > 0) == expected, 'cached match changed')
      end
    end
    for _, query in ipairs({"'Shipment", '^vendor', 'php$', '!Shipment', 'file:Shipment',
      'shipping Other', 'Shipment | Other', 'Shipment.php:12'}) do
      fast:init(query)
      normal:init(query)
      for _, path in ipairs(paths) do
        local item = {file=path, text=path}
        assert(fast:match(item) == normal:match(item), 'advanced syntax changed: ' .. query)
      end
    end
    -- Broad queries must not call the exhaustive path fuzzy scorer.
    fast.fuzzy = function() error('exhaustive fuzzy scorer called') end
    fast:init('sh')
    for _, path in ipairs(paths) do fast:match({file=path, text=path}) end

    local rank = require('core.file-rank')
    local reads = 0
    local frecency = {get=function() reads=reads+1; return 42 end}
    local matcher = {pattern='pprecord', frecency=frecency}
    local item = {file='ParcelProjectionRecord.php', score=10}
    rank.on_match(matcher, item)
    assert(item.file_match_rank == 2 and item.file_usage == 42)
    matcher.pattern = 'ppr'
    item.score = 10
    rank.on_match(matcher, item)
    assert(reads == 1 and item.file_match_rank == 2, 'history was read again per letter')
    matcher.pattern = 'shipment'
    item = {file='Shipment.php', score=10}
    rank.on_match(matcher, item)
    assert(item.file_match_rank == 2 and item.score == 1610, 'prefix ranking changed')
  ]])
  screen:close()
end)
