local lib = require("lib")
local h = require("support")

for _, action in ipairs({ "create", "paste" }) do
  lib.test(
    "HTTP " .. action .. " prompts for only the name with a noneditable .http suffix",
    function()
      local dir = h.tmpdir()
      local screen = h.nvim(dir)
      screen:input("<Space>h")
      h.wait(screen, function()
        return screen:exec("return #require('modules.http_requests').panes() == 1")
      end, "HTTP pane did not open")
      screen:exec([[
      require('modules.http_requests').clipboard = function()
        return 'curl https://example.test/orders'
      end
    ]])
      screen:input(action == "create" and "a" or "P")
      h.wait(screen, function()
        return screen:exec("return vim.bo.filetype == 'snacks_input' and vim.fn.mode() == 'i'")
      end, "filename prompt did not open")
      screen:flush()
      lib.ok(
        h.find_on_screen(screen, "fixed extension") == nil,
        "redundant extension footer is still shown"
      )
      if action == "paste" then
        lib.ok(
          h.find_on_screen(screen, "from copied cURL") ~= nil,
          "filename box does not explain the copied cURL source"
        )
      else
        lib.ok(
          h.find_on_screen(screen, "from copied cURL") == nil,
          "ordinary creation is mislabeled as a cURL import"
        )
      end
      screen:input("orders.v2<End><Del><Del><Del><Del><Del>")
      screen:flush()
      lib.eq(
        "orders.v2",
        screen:exec("return vim.api.nvim_get_current_line()"),
        "suffix became editable text"
      )
      lib.ok(
        h.find_on_screen(screen, "orders.v2.http") ~= nil,
        "fixed extension is not shown after the name"
      )
      screen:input("<CR>")
      h.wait(screen, function()
        return vim.uv.fs_stat(dir .. "/orders.v2.http") ~= nil
      end, "new file did not get the fixed .http extension")
      lib.ok(vim.uv.fs_stat(dir .. "/orders.v2") == nil, "created a file without .http")
      local lines = h.read(dir .. "/orders.v2.http")
      lib.ok(
        vim.tbl_contains(
          lines,
          action == "create" and "GET https://" or "GET https://example.test/orders"
        ),
        "new file has incorrect request contents"
      )
      screen:close()
    end
  )
end

lib.test("HTTP filename normalization always adds exactly one fixed .http extension", function()
  local normalize = require("modules.http_requests.filename").normalize
  lib.eq("orders.http", normalize("orders"))
  lib.eq("orders.v2.http", normalize("orders.v2"))
  lib.eq("orders.json.http", normalize("orders.json"))
  lib.eq("orders.http", normalize(" orders.HTTP "))
  lib.eq("orders.http", normalize("orders.http.http"))
  lib.eq(nil, normalize(nil))
  lib.eq(nil, normalize("  "))
  lib.eq(nil, normalize(".http"))
end)
