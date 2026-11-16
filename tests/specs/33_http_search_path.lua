local lib = require("lib")
local h = require("support")

lib.test("HTTP search keeps each matched request's folder and filename visible", function()
  local dir = h.tmpdir()
  h.write(dir .. "/api/orders/checkout.http", {
    "### Find order",
    "GET https://example.test/orders",
    "### Other request",
    "GET https://example.test/other",
  })
  h.write(dir .. "/billing/refunds.http", { "### Find order", "GET https://example.test/refunds" })
  h.write(dir .. "/unrelated/health.http", { "### Health", "GET https://example.test/health" })
  local screen = h.nvim(dir)
  screen:input("<Space>h")
  h.wait(screen, function()
    return h.find_on_screen(screen, "checkout.http", 40) ~= nil
  end, "HTTP files did not load")
  screen:input("/")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'snacks_picker_input' and vim.fn.mode() == 'i'")
  end, "HTTP search input did not open")
  screen:input("Find order")
  h.wait(screen, function()
    return screen:exec([[
      local p = require('modules.http_requests').panes()[1]
      if not p then return false end
      local names = {}
      for i = 1, p.list:count() do names[#names + 1] = p.list:get(i).text end
      return #names == 6 and names[1] == 'api/orders' and names[2] == 'checkout.http'
        and names[4] == 'billing' and names[5] == 'refunds.http'
    ]])
  end, function()
    return "search did not retain hierarchy: "
      .. vim.inspect(screen:exec([[
      local p = require('modules.http_requests').panes()[1]
      local found = {}
      for i = 1, p.list:count() do found[#found + 1] = p.list:get(i).text end
      return found
    ]]))
  end)
  screen:flush()
  for _, text in ipairs({ "api/orders", "checkout.http", "billing", "refunds.http", "Find order" }) do
    lib.ok(h.find_on_screen(screen, text, 40) ~= nil, "missing search path component: " .. text)
  end
  lib.ok(
    h.find_on_screen(screen, "Other request", 40) == nil,
    "nonmatching request remained in search"
  )
  lib.ok(h.find_on_screen(screen, "health.http", 40) == nil, "unrelated file remained in search")
  screen:input("<CR>")
  h.wait(screen, function()
    return screen:exec(
      "return vim.fn.expand('%:t') == 'checkout.http' and vim.api.nvim_win_get_cursor(0)[1] == 2"
    )
  end, "Enter opened an ancestor instead of the matched request")
  screen:close()
end)

lib.test("HTTP filename search reveals all requests, including a folded file's children", function()
  local dir = h.tmpdir()
  h.write(dir .. "/api/catalog.http", {
    "### List products",
    "GET https://example.test/products",
    "",
    "### Create product",
    "POST https://example.test/products",
  })
  h.write(dir .. "/api/unrelated.http", { "### Health", "GET https://example.test/health" })
  local screen = h.nvim(dir)
  screen:input("<Space>h")
  h.wait(screen, function()
    return screen:exec([[
      local p = require('modules.http_requests').panes()[1]
      if not p then return false end
      for i, item in ipairs(p:items()) do
        if item.kind == 'file' and item.text == 'catalog.http' then
          _G.filename_search_pane = p
          p.list:move(i, true)
          return true
        end
      end
      return false
    ]])
  end, "catalog file did not appear")
  screen:input("h")
  h.wait(screen, function()
    return h.find_on_screen(screen, "List products", 40) == nil
  end, "file did not fold")
  screen:input("/")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'snacks_picker_input' and vim.fn.mode() == 'i'")
  end, "search input did not open")
  screen:input("catalog")
  h.wait(screen, function()
    return screen:exec([[
      local p = _G.filename_search_pane
      local names = {}
      for i=1,p.list:count() do names[#names+1]=p.list:get(i).text end
      return #names == 4 and names[1] == 'api' and names[2] == 'catalog.http'
        and names[3]:find('List products', 1, true) ~= nil
        and names[4]:find('Create product', 1, true) ~= nil
    ]])
  end, "filename-only match did not include all its requests")
  screen:flush()
  lib.ok(h.find_on_screen(screen, "List products", 40) ~= nil, "first request is not shown")
  lib.ok(h.find_on_screen(screen, "Create product", 40) ~= nil, "second request is not shown")
  lib.ok(h.find_on_screen(screen, "unrelated.http", 40) == nil, "unrelated file is shown")
  screen:input("<Esc>")
  h.wait(screen, function()
    return screen:exec([[
      local p = _G.filename_search_pane
      return vim.api.nvim_get_current_win() == p.list.win.win
        and p.input.filter.pattern == 'catalog' and p.list:count() == 4
    ]])
  end, "Escape did not focus the filtered results without clearing the query")
  for _, step in ipairs({
    { "j", "List products", 2 },
    { "j", "Create product", 5 },
    { "k", "List products", 2 },
  }) do
    screen:input(step[1])
    h.wait(screen, function()
      return screen:exec(
        [[
        local name, line = ...
        local p = _G.filename_search_pane
        local item = p:current()
        if not item or not item.req or item.req.name ~= name then return false end
        local matches = vim.tbl_filter(function(m) return m.group == 'HttpRequestSelectedName' end, vim.fn.getmatches(p.main))
        return vim.api.nvim_get_current_win() == p.list.win.win
          and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(p.main)), ':t') == 'catalog.http'
          and vim.api.nvim_win_get_cursor(p.main)[1] == line
          and #matches == 1 and matches[1].pos1[1] == item.req.name_line
      ]],
        { step[2], step[3] }
      )
    end, "moving through filtered results did not preview/highlight " .. step[2])
  end
  screen:input("<Esc>")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'snacks_picker_list'")
      and h.find_on_screen(screen, "List products", 40) == nil
  end, "clearing search lost the original folded state")
  screen:close()
end)

for _, action in ipairs({ "Enter", "click" }) do
  lib.test("HTTP " .. action .. " on a filename opens that file instead of folding it", function()
    local dir = h.tmpdir()
    h.write(dir .. "/requests.http", { "### List", "GET https://example.test/list" })
    local screen = h.nvim(dir)
    screen:input("<Space>h")
    h.wait(screen, function()
      return h.find_on_screen(screen, "requests.http", 40) ~= nil
    end, "filename did not appear")
    screen:flush()
    if action == "click" then
      local row, col = h.find_on_screen(screen, "requests.http", 40)
      h.click(screen, row, col + 1)
    else
      screen:exec([[
        local p = require('modules.http_requests').panes()[1]
        for i, item in ipairs(p:items()) do
          if item.kind == 'file' then p.list:move(i, true); break end
        end
      ]])
      screen:input("<CR>")
    end
    h.wait(screen, function()
      return screen:exec("return vim.fn.expand('%:t') == 'requests.http' and vim.bo.buftype == ''")
    end, action .. " did not open the HTTP file")
    lib.eq(
      1,
      screen:exec("return #require('modules.http_requests').panes()"),
      "opening the file closed the HTTP pane"
    )
    screen:close()
  end)
end
