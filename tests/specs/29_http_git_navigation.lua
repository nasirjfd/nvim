local lib = require("lib")
local h = require("support")

for _, startup in ipairs({
  { name = "dashboard", args = {} },
  { name = "directory Explorer", args = { "." } },
  { name = "file", args = { "notes.txt" } },
}) do
  lib.test(
    "HTTP navigation after Git never replaces the pane with Explorer from " .. startup.name,
    function()
      local dir = h.repo({ ["notes.txt"] = { "notes" } })
      for i = 1, 8 do
        h.write(dir .. "/requests/" .. i .. ".http", {
          "### Request " .. i,
          "GET https://example.test/" .. i,
          "",
          "### Second request " .. i,
          "GET https://example.test/" .. i .. "/second",
        })
      end
      local screen = h.nvim(dir, 160, 45, startup.args)
      if startup.name == "directory Explorer" then
        h.wait(screen, function()
          return screen:exec("return #Snacks.picker.get({ source = 'explorer' }) == 1")
        end, "startup Explorer did not open")
      end
      screen:input("<D-S-g>")
      h.wait(screen, function()
        return screen:exec("return vim.bo.filetype == 'codediff-explorer'")
      end, "Git pane did not open")
      screen:input("<D-S-h>")
      h.wait(screen, function()
        return screen:exec("return #require('modules.http_requests').panes() == 1")
      end, "HTTP pane did not open")
      h.wait(screen, function()
        return h.find_on_screen(screen, "Request 8") ~= nil
      end, "HTTP requests did not load")
      screen:exec(
        "_G.http_navigation_pane = require('modules.http_requests').panes()[1]; _G.http_navigation_tab = vim.api.nvim_get_current_tabpage()"
      )
      for _ = 1, 24 do
        screen:input("j")
        screen:flush()
        lib.ok(
          screen:exec([[
      local p = _G.http_navigation_pane
      return not p.closed and vim.api.nvim_get_current_win() == p.list.win.win
    ]]),
          "j left the HTTP pane: "
            .. vim.inspect(screen:exec([[
      return {ft=vim.bo.filetype, name=vim.api.nvim_buf_get_name(0),
        explorers=#Snacks.picker.get({source='explorer'}),
        http=#require('modules.http_requests').panes()}
    ]]))
        )
        if screen:exec("return (_G.http_navigation_pane:current() or {}).kind == 'request'") then
          h.wait(screen, function()
            return screen:exec([[
              local p = _G.http_navigation_pane
              local item = p:current()
              return vim.api.nvim_win_is_valid(p.main)
                and vim.api.nvim_win_get_tabpage(p.main) == _G.http_navigation_tab
                and vim.fs.normalize(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(p.main))) == vim.fs.normalize(item.file)
                and vim.api.nvim_win_get_cursor(p.main)[1] == item.req.line
            ]])
          end, "request preview is not visible beside the HTTP pane")
        end
      end
      lib.ok(
        screen:exec([[
    local p = _G.http_navigation_pane
    return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(p.main)):match('%.http$') ~= nil
  ]]),
        "navigation never previewed a request in an editor window"
      )
      screen:exec("_G.http_enter_item = _G.http_navigation_pane:current()")
      screen:input("<CR>")
      h.wait(screen, function()
        return screen:exec([[
          local p = _G.http_navigation_pane
          return not p.closed and vim.api.nvim_get_current_tabpage() == _G.http_navigation_tab
            and vim.api.nvim_get_current_win() == p.main
            and vim.fn.expand('%:e') == 'http'
            and vim.api.nvim_win_get_cursor(0)[1] == _G.http_enter_item.req.line
        ]])
      end, "Enter did not focus the adjacent HTTP editor")
      screen:close()
    end
  )
end
