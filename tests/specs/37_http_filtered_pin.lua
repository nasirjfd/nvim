local lib = require("lib")
local h = require("support")

lib.test("HTTP filtered pin honors the navigated request instead of the first match", function()
  local dir = h.tmpdir()
  h.write(dir .. "/login.http", { "### Login first", "POST https://example.test/login" })
  h.write(dir .. "/post-payment.http", {
    "### Login payment",
    "POST https://example.test/payment/login",
    "### Login last",
    "POST https://example.test/payment/last-login",
  })
  local screen = h.nvim(dir)
  screen:input("<Space>h")
  h.wait(screen, function()
    return screen:exec("return #require('modules.http_requests').panes() == 1")
  end, "HTTP pane did not open")
  screen:input("/")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'snacks_picker_input' and vim.fn.mode() == 'i'")
  end, "search input did not open")
  screen:input("login")
  h.wait(screen, function()
    return screen:exec([[
      local p = require('modules.http_requests').panes()[1]
      local count = 0
      for i=1,p.list:count() do if p.list:get(i).kind == 'request' then count=count+1 end end
      return count == 3 and not p.finder:running()
    ]])
  end, "search did not settle")
  screen:input("<Esc>")
  vim.wait(250)
  screen:input("G")
  h.wait(screen, function()
    return screen:exec([[
      local p = require('modules.http_requests').panes()[1]
      local item = p:current()
      return vim.api.nvim_get_current_win() == p.list.win.win
        and item and item.req and item.req.name == 'Login last'
    ]])
  end, "last result was not selected")
  screen:input("p")
  h.wait(screen, function()
    return screen:exec([[
      local pins = require('modules.http_requests.pinned').list(vim.uv.cwd())
      return #pins == 1 and pins[1].file == 'post-payment.http' and pins[1].name == 'Login last'
    ]])
  end, function()
    return vim.inspect(screen:exec([[
    local p=require('modules.http_requests').panes()[1]
    return {pins=require('modules.http_requests.pinned').list(vim.uv.cwd()), item=p:current(), cwd=vim.uv.cwd(), messages=vim.fn.execute('messages')}
  ]]))
  end)
  screen:input("p")
  h.wait(screen, function()
    return screen:exec("return #require('modules.http_requests.pinned').list(vim.uv.cwd()) == 0")
  end, "second p did not unpin the same selected request")
  screen:close()
end)
