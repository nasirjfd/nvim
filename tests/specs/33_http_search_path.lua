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
