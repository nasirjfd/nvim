-- ============================================================================
-- One sidebar at a time: the Snacks file explorer and the codediff sidebar (the changed-files list,
-- history or the multi-repo Source Control pane) of a tab. Showing one hides the other.
-- ============================================================================
local group = vim.api.nvim_create_augroup("SidebarExclusive", { clear = true })

local M = {}

-- The last codediff sidebar of each tab. Opening a file over the diff panes ends the codediff
-- session but leaves the sidebar on screen, so it is remembered here to keep toggling it.
local panels = {}
-- Tabs where the file explorer was opened last: <D-b> toggles that instead of the codediff sidebar.
local explorer_pref = {}
-- The sidebar opened last in each tab: "explorer", "codediff" or "http" (the HTTP Requests pane).
local last_sidebar = {}

function M.last(tab)
  return last_sidebar[tab]
end

-- The source ("explorer", "http_requests", …) of the picker whose list is shown in `buf`.
local function source_of(buf)
  if not _G.Snacks or not Snacks.picker then
    return nil
  end
  for _, picker in ipairs(Snacks.picker.get()) do
    local list = picker.list and picker.list.win
    if list and list.buf == buf then
      return picker.opts.source
    end
  end
end

-- The HTTP Requests panes shown in `tab`.
local function http_panes(tab)
  local ok, http = pcall(require, "modules.http_requests")
  return ok and http.panes(tab) or {}
end

-- Close a Snacks picker *now*, windows included. picker:close() destroys its windows one tick later; a
-- second sidebar opened in between makes Neovim split the screen between the two layouts and hand the
-- rows it cannot place to the command line (cmdheight 20, the sidebar and the editor half as tall).
local function close_now(picker)
  if picker.closed then
    return
  end
  picker:close()
  pcall(function()
    picker.layout:close()
  end)
end
M.close_now = close_now

-- Whatever happened, the command line is one row (the option in core/options.lua)
local function restore_cmdheight()
  if vim.o.cmdheight ~= 1 then
    vim.o.cmdheight = 1
  end
end

local function codediff_panel(tab)
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  local live = lifecycle and lifecycle.get_panel_view(tab)
  if live then
    panels[tab] = live
    return live
  end
  local old = panels[tab]
  if old and old.split and old.split.bufnr and vim.api.nvim_buf_is_valid(old.split.bufnr) then
    return old
  end
end

-- The codediff sidebar of `tab` after its session has ended (nil while the session is alive).
function M.orphan_panel(tab)
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  if lifecycle and lifecycle.get_panel_view(tab) then
    return nil
  end
  return codediff_panel(tab)
end

function M.prefers_explorer(tab)
  return explorer_pref[tab] == true
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
      if not vim.api.nvim_tabpage_is_valid(tab) or #snacks_explorers(tab) == 0 or source_of(args.buf) ~= "explorer" then
        return
      end
      explorer_pref[tab] = true
      last_sidebar[tab] = "explorer"
      for _, picker in ipairs(http_panes(tab)) do
        close_now(picker)
      end
      restore_cmdheight()
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
      explorer_pref[tab] = false
      last_sidebar[tab] = "codediff"
      codediff_panel(tab)
      for _, picker in ipairs(snacks_explorers(tab)) do
        close_now(picker)
      end
      for _, picker in ipairs(http_panes(tab)) do
        close_now(picker)
      end
      restore_cmdheight()
    end)
  end,
})

-- The HTTP Requests pane appeared: close the file explorer and hide the codediff sidebar of the tab.
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    if vim.bo[args.buf].filetype ~= "snacks_picker_list" then
      return
    end
    local tab = vim.api.nvim_get_current_tabpage()
    vim.schedule(function()
      if not vim.api.nvim_tabpage_is_valid(tab) or #http_panes(tab) == 0 or source_of(args.buf) ~= "http_requests" then
        return
      end
      last_sidebar[tab] = "http"
      for _, picker in ipairs(snacks_explorers(tab)) do
        close_now(picker)
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

-- Called by the HTTP Requests pane right before it opens: nothing else may be a sidebar at that moment.
function M.make_room_for_http(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  for _, picker in ipairs(snacks_explorers(tab)) do
    close_now(picker)
  end
  local panel = codediff_panel(tab)
  if panel_visible(panel) then
    local previous = vim.api.nvim_get_current_win()
    pcall(require("codediff.ui.explorer").toggle_visibility, panel)
    if vim.api.nvim_win_is_valid(previous) then
      vim.api.nvim_set_current_win(previous)
    end
  end
  restore_cmdheight()
end

-- The file explorer is about to open (Snacks.explorer(), <leader>e, cmd+b, …): close the HTTP pane first,
-- for the same reason as in close_now. Every way of opening it goes through Snacks.picker.pick.
vim.api.nvim_create_autocmd("VimEnter", {
  group = group,
  once = true,
  callback = function()
    if not (_G.Snacks and Snacks.picker and Snacks.picker.pick) or Snacks.picker._sidebars_wrapped then
      return
    end
    local pick = Snacks.picker.pick
    Snacks.picker.pick = function(source, opts)
      local name = type(source) == "table" and source.source or source
      if name == "explorer" and #snacks_explorers(vim.api.nvim_get_current_tabpage()) == 0 then
        for _, picker in ipairs(http_panes(vim.api.nvim_get_current_tabpage())) do
          close_now(picker)
        end
      end
      return pick(source, opts)
    end
    Snacks.picker._sidebars_wrapped = true
  end,
})

return M
