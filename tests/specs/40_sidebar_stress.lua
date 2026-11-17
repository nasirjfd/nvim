local lib = require("lib")
local h = require("support")

lib.test("diff panes remain centered after shortcut bursts and sidebar close", function()
  local dir = h.repo({ ["a.txt"] = { "one", "two" }, ["api.http"] = { "GET https://example.com" } })
  h.write(dir .. "/a.txt", { "one", "changed" })
  local screen = h.nvim(dir)
  screen:input("<D-S-g>")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'codediff-explorer'")
  end, "Git did not open")
  screen:exec([[
    _G.diff_tab = vim.api.nvim_get_current_tabpage()
    local panel = require("codediff.ui.lifecycle").get_panel_view(_G.diff_tab)
    panel.on_file_select({ path = "a.txt", group = "unstaged", status = "M", git_root = vim.fn.getcwd() })
  ]])
  h.wait(screen, function()
    return screen:exec([[
      local session = require("codediff.ui.lifecycle").get_session(_G.diff_tab)
      return session and not session.single_pane and session.stored_diff_result
        and session.stored_diff_result.changes and #session.stored_diff_result.changes > 0
    ]])
  end, "file diff did not load")
  for _ = 1, 10 do
    screen:input("<D-S-e><D-S-h><D-S-t><D-S-g>")
    vim.wait(40)
  end
  screen:input("<D-S-g>")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'codediff-explorer'")
  end, "Git did not regain focus")
  screen:input("<D-b>")
  h.wait(screen, function()
    return screen:exec([[
      local session = require("codediff.ui.lifecycle").get_session(_G.diff_tab)
      local panel = session and session.panel and session.panel.view
      return session and panel and panel.is_hidden
        and math.abs(vim.api.nvim_win_get_width(session.original_win)
          - vim.api.nvim_win_get_width(session.modified_win)) <= 1
    ]])
  end, "diff panes are uneven after hiding the sidebar")
  screen:close()
end)

lib.test("real shortcut bursts end in Git without foreign sidebars in any tab", function()
  -- Optional read-only run against a real workspace; fixture mutations are never used there.
  local dir = vim.env.NVIM_SIDEBAR_STRESS_PROJECT
  if not dir then
    dir = h.repo({ ["a.txt"] = { "one", "two" }, ["api.http"] = { "GET https://example.com" } })
    h.write(dir .. "/a.txt", { "one", "changed" })
  end
  local screen = h.nvim(dir)
  if vim.env.NVIM_SIDEBAR_STRESS_PROJECT then
    screen:exec(
      "dofile(vim.fn.getcwd() .. '/.nvim.lua'); require('codediff.config').options.scm.auto_fetch = false"
    )
  end
  screen:input("<D-S-g>")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'codediff-explorer'")
  end, "Git never opened")
  for _ = 1, 12 do
    screen:input(("<D-S-e><D-S-h><D-S-t><D-S-g>"):rep(5))
    vim.wait(30)
  end
  screen:input("<D-S-g>")
  vim.wait(1800)
  lib.eq("codediff-explorer", screen:exec("return vim.bo.filetype"), "last shortcut must focus Git")
  local state = screen:exec([[
    local tabs = {}
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      local wins = {}
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        local cfg = vim.api.nvim_win_get_config(win)
        wins[#wins + 1] = { ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype,
          relative = cfg.relative, hide = cfg.hide or false }
      end
      tabs[#tabs + 1] = wins
    end
    return tabs
  ]])
  for _, wins in ipairs(state) do
    local git, snacks, boxes = 0, 0, 0
    for _, win in ipairs(wins) do
      git = git + (win.ft == "codediff-explorer" and 1 or 0)
      snacks = snacks + (win.ft == "snacks_picker_list" and not win.hide and 1 or 0)
      boxes = boxes + (win.ft == "snacks_layout_box" and 1 or 0)
    end
    lib.ok(
      git <= 1 and snacks <= 1 and boxes <= 1 and not (git > 0 and (snacks > 0 or boxes > 0)),
      vim.inspect(state)
    )
  end
  screen:input("<D-S-e>")
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'explorer' }) == 1")
  end, "Explorer did not open after the burst")
  screen:input("<D-b>")
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'explorer' }) == 0")
  end, "Cmd+B did not close Explorer after the burst")
  screen:close()
end)

for _, final in ipairs({
  { key = "<D-S-e>", source = "explorer" },
  { key = "<D-S-h>", source = "http_requests" },
  { key = "<D-S-t>", source = "phpunit_tests" },
}) do
  lib.test("shortcut bursts settle exclusively on " .. final.source, function()
    local dir = h.repo({ ["api.http"] = { "GET https://example.com" } })
    local screen = h.nvim(dir)
    screen:input("<D-S-g>")
    h.wait(screen, function()
      return screen:exec("return vim.bo.filetype == 'codediff-explorer'")
    end, "Git did not open")
    for _ = 1, 8 do
      screen:input(("<D-S-h><D-S-e><D-S-g><D-S-t>"):rep(3))
      vim.wait(20)
    end
    screen:input(final.key)
    h.wait(screen, function()
      return screen:exec(
        [[
        local pickers = Snacks.picker.get({ source = ..., tab = false })
        return #pickers == 1 and pickers[1].list.win.win == vim.api.nvim_get_current_win()
      ]],
        { final.source }
      )
    end, function()
      return "final pane did not receive focus: "
        .. vim.inspect(screen:exec([[
        local tabs = {}
        for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
          local wins = {}
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
            wins[#wins + 1] = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
          end
          tabs[#tabs + 1] = { target = require("core.sidebars").target(tab), wins = wins }
        end
        return { focus = vim.bo.filetype, tabs = tabs }
      ]]))
    end)
    vim.wait(800)
    lib.ok(
      screen:exec([[
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        local git, lists, boxes = 0, 0, 0
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
          local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
          git = git + (ft == "codediff-explorer" and 1 or 0)
          lists = lists + (ft == "snacks_picker_list" and 1 or 0)
          boxes = boxes + (ft == "snacks_layout_box" and 1 or 0)
        end
        if git > 1 or lists > 1 or boxes > 1 or (git > 0 and boxes > 0) then return false end
      end
      return vim.o.cmdheight == 1
    ]]),
      "sidebars overlapped after final " .. final.source
    )
    screen:close()
  end)
end
