local lib = require("lib")
local h = require("support")

local function open()
  local dir = h.tmpdir()
  for file = 1, 2 do
    local lines = {}
    for i = 1, 40 do
      vim.list_extend(lines, {
        ("### Request_%d_%02d"):format(file, i),
        i % 2 == 0 and ("# @name named_%d_%02d"):format(file, i) or "# comment",
        "GET https://example.test/" .. i,
        "",
      })
      for _ = 1, 10 do
        lines[#lines + 1] = "# request body context"
      end
    end
    h.write(dir .. "/" .. file .. ".http", lines)
  end
  local screen = h.nvim(dir)
  screen:input("<Space>h")
  h.wait(screen, function()
    return screen:exec([[
      local p = require('modules.http_requests').panes()[1]
      if not p or #p:items() < 83 then return false end
      _G.preview_test_pane = p
      return true
    ]])
  end, "requests did not load")
  screen:exec([[
    _G.check_http_preview = function()
      local p = _G.preview_test_pane
      local item = p:current()
      if item.kind ~= 'request' then return end
      local win, req = p.main, item.req
      assert(vim.api.nvim_get_current_win() == p.list.win.win, 'preview took focus')
      assert(vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage(), 'preview is in another tab')
      local buf = vim.api.nvim_win_get_buf(win)
      assert(vim.api.nvim_buf_get_name(buf) == item.file, 'preview shows the previous file')
      assert(vim.api.nvim_win_get_cursor(win)[1] == req.line, 'preview cursor lags behind selection')
      local matches = vim.tbl_filter(function(m) return m.group == 'HttpRequestSelectedName' end, vim.fn.getmatches(win))
      assert(#matches == 1, 'expected exactly one selected request-name highlight')
      assert(vim.deep_equal(matches[1].pos1, {req.name_line, req.name_col + 1, req.name_end - req.name_col}),
        'name highlight lags behind selection')
      local text = vim.api.nvim_buf_get_lines(buf, req.name_line - 1, req.name_line, false)[1]
      assert(text:sub(req.name_col + 1, req.name_end) == req.name, 'highlight covers the wrong name')
    end
  ]])
  return screen
end

lib.test("HTTP fast j/k highlights every exact request name without waiting for idle", function()
  local screen = open()
  for _ = 1, 70 do
    screen:input("j")
    screen:exec("_G.check_http_preview()")
  end
  for _ = 1, 45 do
    screen:input("k")
    screen:exec("_G.check_http_preview()")
  end
  local before = screen:exec("return _G.preview_test_pane.list.cursor")
  screen:input(string.rep("j", 15) .. string.rep("k", 7))
  lib.eq(
    before + 8,
    screen:exec("_G.check_http_preview(); return _G.preview_test_pane.list.cursor"),
    "a burst of keys left preview updates queued"
  )
  screen:flush()
  local selected = screen:exec("return _G.preview_test_pane:current().req.name")
  local row = h.find_on_screen(screen, selected)
  lib.ok(row ~= nil, "selected request name is not on screen")
  local position = screen:exec([[
    local p = _G.preview_test_pane
    local req = p:current().req
    return vim.api.nvim_win_call(p.main, function()
      return vim.fn.screenpos(p.main, req.name_line, req.name_col + 1)
    end)
  ]])
  local color =
    screen:exec("return vim.api.nvim_get_hl(0, {name='HttpRequestSelectedName', link=false})")
  lib.eq(
    color.bg,
    screen:highlight(position.row, position.col).background,
    "right-hand name is not visibly highlighted"
  )
  screen:exec("_G.preview_test_pane:close()")
  h.wait(screen, function()
    return screen:exec([[
      return #vim.tbl_filter(function(m) return m.group == 'HttpRequestSelectedName' end,
        vim.fn.getmatches(_G.preview_test_pane.main)) == 0
    ]])
  end, "closing HTTP left a stale highlight")
  screen:close()
end)

lib.test(
  "HTTP preview handles rapid synchronous moves across files without a delayed backlog",
  function()
    local screen = open()
    local ms = screen:exec([[
    local p = _G.preview_test_pane
    -- the editor's own CPU time, not the wall clock: other tests running at the same moment (parallel
    -- workers) slow the clock down, not the work this measures
    local function cpu()
      local u = vim.uv.getrusage()
      return (u.utime.sec + u.stime.sec) * 1e3 + (u.utime.usec + u.stime.usec) / 1e3
    end
    local start = cpu()
    for pass = 1, 3 do
      for _ = 1, 82 do p:action('http_down'); _G.check_http_preview() end
      for _ = 1, 82 do p:action('http_up'); _G.check_http_preview() end
    end
    return cpu() - start
  ]])
    lib.ok(ms < 2000, ("492 moves took %.0fms; request preview blocks navigation"):format(ms))
    print(("    492 synchronous preview moves: %.0fms"):format(ms))
    screen:close()
  end
)

lib.test(
  "HTTP request-name spans identify titles, @name tags and unnamed requests exactly",
  function()
    local lines = {
      "### A title with spaces",
      "GET https://example.test/a",
      "### Ignored title",
      "# @name name",
      "GET https://example.test/b",
      "###",
      "  GET https://example.test/c",
    }
    local requests = require("modules.http_requests.parse").parse(lines)
    for i, req in ipairs(requests) do
      lib.eq(
        req.name,
        lines[req.name_line]:sub(req.name_col + 1, req.name_end),
        "wrong name span for request " .. i
      )
    end
    lib.eq(
      { 1, 4, 7 },
      vim.tbl_map(function(req)
        return req.name_line
      end, requests)
    )
    lib.eq(8, requests[2].name_col, "@name's label was highlighted instead of its value")
  end
)
