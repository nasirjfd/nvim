local lib = require("lib")
local h = require("support")

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
  screen:close()
end)
