-- ============================================================================
-- One sidebar at a time: the Snacks file explorer and the codediff sidebar (the changed-files list,
-- history or the multi-repo Source Control pane) of a tab. Showing one hides the other.
-- ============================================================================
local group = vim.api.nvim_create_augroup("SidebarExclusive", { clear = true })

local function codediff_panel(tab)
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  return lifecycle and lifecycle.get_panel_view(tab)
end

local function panel_visible(panel)
  return panel and not panel.is_hidden and panel.split and panel.split.winid and vim.api.nvim_win_is_valid(panel.split.winid)
end

-- The Snacks explorer pickers whose list is shown in `tab`.
local function snacks_explorers(tab)
  local found = {}
  if not _G.Snacks or not Snacks.picker then
    return found
  end
  for _, picker in ipairs(Snacks.picker.get({ source = "explorer" })) do
    local win = picker.list and picker.list.win and picker.list.win.win
    if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_tabpage(win) == tab then
      found[#found + 1] = picker
    end
  end
  return found
end

-- The file explorer appeared: hide the codediff sidebar of the tab.
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    if vim.bo[args.buf].filetype ~= "snacks_picker_list" then
      return
    end
    local tab = vim.api.nvim_get_current_tabpage()
    vim.schedule(function()
      if not vim.api.nvim_tabpage_is_valid(tab) or #snacks_explorers(tab) == 0 then
        return
      end
      local panel = codediff_panel(tab)
      if panel_visible(panel) then
        local previous = vim.api.nvim_get_current_win()
        require("codediff.ui.explorer").toggle_visibility(panel)
        if vim.api.nvim_win_is_valid(previous) then
          vim.api.nvim_set_current_win(previous)
        end
      end
    end)
  end,
})

-- The codediff sidebar appeared: close the file explorer of the tab.
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    local filetype = vim.bo[args.buf].filetype
    if filetype ~= "codediff-explorer" and filetype ~= "codediff-history" then
      return
    end
    local tab = vim.api.nvim_get_current_tabpage()
    vim.schedule(function()
      if not vim.api.nvim_tabpage_is_valid(tab) then
        return
      end
      for _, picker in ipairs(snacks_explorers(tab)) do
        picker:close()
      end
    end)
  end,
})
