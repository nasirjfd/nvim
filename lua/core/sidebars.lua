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
-- The sidebar opened last in each tab: "explorer", "codediff", "http" (HTTP Requests) or "tests".
local last_sidebar = {}
-- The sidebar currently being opened. Scheduled BufWinEnter cleanup from an older picker must never
-- be allowed to close a newer one while the user switches panes quickly.
local target_sidebar = {}
local request_id = {} -- per-tab generation: delayed directory opens yield to explicit pane/picker requests
local switch_id = 0

-- Coalesce rapid pane shortcuts before constructing layouts. This is shared across tabs: Git and
-- HTTP can navigate to different tabs, so per-tab generations alone cannot order user intent.
function M.switch(callback)
  switch_id = switch_id + 1
  local id = switch_id
  local scm = package.loaded["codediff.commands.handlers.scm"]
  if scm and scm.cancel_pending then
    scm.cancel_pending()
  end
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    M.request(tab)
  end
  vim.defer_fn(function()
    if id == switch_id then
      callback()
      M.reconcile()
    end
  end, 20)
end

function M.request(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  request_id[tab] = (request_id[tab] or 0) + 1
  return request_id[tab]
end

function M.generation(tab)
  return request_id[tab or vim.api.nvim_get_current_tabpage()] or 0
end

function M.last(tab)
  return last_sidebar[tab]
end

function M.target(tab)
  return target_sidebar[tab or vim.api.nvim_get_current_tabpage()]
end

-- The source ("explorer", "http_requests", …) of the picker whose list is shown in `buf`.
local function source_of(buf)
  if not _G.Snacks or not Snacks.picker then
    return nil
  end
  for _, picker in ipairs(Snacks.picker.get({ tab = false })) do
    local list = picker.list and picker.list.win
    if list and list.buf == buf then
      return picker.opts.source
    end
  end
end

-- The panes built on a Snacks picker besides the explorer: name -> picker source.
local EXTRA = { http = "http_requests", tests = "phpunit_tests" }

-- The extra panes (HTTP Requests, Tests) shown in `tab`, except the one called `except`.
local function extra_panes(tab, except)
  local found = {}
  local kit = require("modules.pane_kit")
  for name, source in pairs(EXTRA) do
    if name ~= except then
      vim.list_extend(found, kit.panes(source, tab))
    end
  end
  return found
end

local function name_of_source(source)
  for name, candidate in pairs(EXTRA) do
    if candidate == source then
      return name
    end
  end
end

-- Close a Snacks picker *now*, windows included. picker:close() destroys its windows one tick later; a
-- second sidebar opened in between makes Neovim split the screen between the two layouts and hand the
-- rows it cannot place to the command line (cmdheight 20, the sidebar and the editor half as tall).
local function close_now(picker)
  if not picker.closed then
    picker:close()
  end
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
  return panel
    and not panel.is_hidden
    and panel.split
    and panel.split.winid
    and vim.api.nvim_win_is_valid(panel.split.winid)
end

-- Include pending pickers: Snacks' default get() excludes layouts without a valid root window.
-- Those must be cancelled too, before their asynchronous show runs in a different tab.
local function snacks_explorers(tab)
  local found = {}
  if not _G.Snacks or not Snacks.picker then
    return found
  end
  for _, picker in ipairs(Snacks.picker.get({ source = "explorer", tab = false })) do
    local win = picker.list and picker.list.win and picker.list.win.win
    if
      picker._sidebar_tab == tab
      or (win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_tabpage(win) == tab)
    then
      found[#found + 1] = picker
    end
  end
  return found
end

function M.toggle_explorer()
  local tab = vim.api.nvim_get_current_tabpage()
  local explorers = snacks_explorers(tab)
  if #explorers > 0 then
    M.request(tab)
    target_sidebar[tab] = "none"
    for _, picker in ipairs(explorers) do
      close_now(picker)
    end
  else
    Snacks.explorer.open()
  end
end

-- Enforce the invariant from actual windows, not just a plugin's cached visibility flag. Window
-- creation, async layout updates, and tab restores all pass through here. Never touch file splits.
local reconciling = false
function M.reconcile()
  if reconciling or not _G.Snacks then
    return
  end
  reconciling = true
  local ok, err = pcall(function()
    local keep = {}
    for _, picker in ipairs(Snacks.picker.get({ tab = false })) do
      local source = picker.opts.source
      local name = source == "explorer" and "explorer" or name_of_source(source)
      if name then
        local win = picker.list and picker.list.win and picker.list.win.win
        local actual_tab = win
          and vim.api.nvim_win_is_valid(win)
          and vim.api.nvim_win_get_tabpage(win)
        local tab = picker._sidebar_tab or actual_tab
        local target = tab and M.target(tab)
        if tab then
          if (actual_tab and actual_tab ~= tab) or (target and target ~= name) then
            close_now(picker)
          elseif keep[tab] then
            close_now(keep[tab])
            keep[tab] = picker
          else
            keep[tab] = picker
          end
        end
      end
    end
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      local target = M.target(tab)
      if target and target ~= "codediff" then
        local panel = codediff_panel(tab)
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
          local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
          if ft == "codediff-explorer" or ft == "codediff-history" then
            vim.api.nvim_win_hide(win)
            if panel then
              panel.is_hidden = true
              if panel.split and panel.split.winid == win then
                panel.split.winid = nil
                panel.winid = nil
              end
            end
          end
        end
      end
    end
    restore_cmdheight()
  end)
  reconciling = false
  if not ok then
    vim.notify("Sidebar reconciliation: " .. tostring(err), vim.log.levels.ERROR)
  end
end

local reconcile_pending = false
vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter", "TabEnter", "WinNew" }, {
  group = group,
  callback = function()
    if reconcile_pending or reconciling then
      return
    end
    reconcile_pending = true
    vim.schedule(function()
      reconcile_pending = false
      M.reconcile()
    end)
  end,
})

-- The file explorer appeared: hide the codediff sidebar of the tab.
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    if vim.bo[args.buf].filetype ~= "snacks_picker_list" then
      return
    end
    local tab = vim.api.nvim_get_current_tabpage()
    local generation = M.generation(tab)
    vim.schedule(function()
      if
        not vim.api.nvim_tabpage_is_valid(tab)
        or M.generation(tab) ~= generation
        or M.target(tab) ~= "explorer"
        or #snacks_explorers(tab) == 0
        or source_of(args.buf) ~= "explorer"
      then
        return
      end
      explorer_pref[tab] = true
      last_sidebar[tab] = "explorer"
      for _, picker in ipairs(extra_panes(tab)) do
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

-- The codediff sidebar appeared: close the Explorer rather than hiding it. Snacks' sidebar layout
-- includes a normal split box; hiding only its floats leaves an empty "Explorer" split behind.
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    local filetype = vim.bo[args.buf].filetype
    if filetype ~= "codediff-explorer" and filetype ~= "codediff-history" then
      return
    end
    local tab = vim.api.nvim_get_current_tabpage()
    local generation = M.generation(tab)
    vim.schedule(function()
      if not vim.api.nvim_tabpage_is_valid(tab) or M.generation(tab) ~= generation then
        return
      end
      if M.target(tab) ~= "codediff" then
        return
      end
      -- A later request may already have hidden Git before this callback gets its turn.
      -- Do not let the stale BufWinEnter callback switch the active-sidebar preference back.
      if not panel_visible(codediff_panel(tab)) then
        return
      end
      explorer_pref[tab] = false
      last_sidebar[tab] = "codediff"
      codediff_panel(tab)
      for _, picker in ipairs(snacks_explorers(tab)) do
        close_now(picker)
      end
      for _, picker in ipairs(extra_panes(tab)) do
        close_now(picker)
      end
      restore_cmdheight()
    end)
  end,
})

-- Esc never hides the regular CodeDiff sidebar, but a commit diff keeps its back-to-graph key.
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    local filetype = vim.bo[args.buf].filetype
    if filetype ~= "codediff-explorer" and filetype ~= "codediff-history" then
      return
    end
    local tab = vim.api.nvim_get_current_tabpage()
    vim.schedule(function()
      local lifecycle = package.loaded["codediff.ui.lifecycle"]
      local session = lifecycle and lifecycle.get_session(tab)
      if session and session.back then
        return
      end
      if vim.api.nvim_buf_is_valid(args.buf) then
        vim.keymap.set(
          "n",
          "<Esc>",
          "<Nop>",
          { buffer = args.buf, silent = true, desc = "Keep Git sidebar open" }
        )
      end
    end)
  end,
})

-- An extra pane (HTTP Requests, Tests) appeared: hide the file explorer and other extra pane, hide the
-- codediff sidebar of the tab.
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    if vim.bo[args.buf].filetype ~= "snacks_picker_list" then
      return
    end
    local tab = vim.api.nvim_get_current_tabpage()
    local generation = M.generation(tab)
    vim.schedule(function()
      local name = vim.api.nvim_tabpage_is_valid(tab)
        and M.generation(tab) == generation
        and name_of_source(source_of(args.buf))
      if not name or M.target(tab) ~= name then
        return
      end
      last_sidebar[tab] = name
      for _, picker in ipairs(snacks_explorers(tab)) do
        close_now(picker)
      end
      for _, picker in ipairs(extra_panes(tab, name)) do
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

-- Called by an extra pane ("http", "tests") right before it opens: close the other sidebars in the
-- same tick, before their layouts can overlap.
function M.make_room(name, tab, keep)
  tab = tab or vim.api.nvim_get_current_tabpage()
  M.request(tab)
  target_sidebar[tab] = name
  last_sidebar[tab] = name
  explorer_pref[tab] = name == "explorer"
  for _, picker in ipairs(snacks_explorers(tab)) do
    if picker ~= keep then
      close_now(picker)
    end
  end
  for _, picker in ipairs(extra_panes(tab, name)) do
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

-- Called right before the codediff sidebar (Git pane) is shown: close every other sidebar at
-- once. The BufWinEnter handler above does it one tick later, and for that tick two sidebars are on
-- screen (a visible jump).
function M.make_room_for_codediff(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  M.request(tab)
  target_sidebar[tab] = "codediff"
  for _, picker in ipairs(snacks_explorers(tab)) do
    close_now(picker)
  end
  for _, picker in ipairs(extra_panes(tab)) do
    close_now(picker)
  end
  restore_cmdheight()
end

function M.make_room_for_http(tab)
  M.make_room("http", tab)
end

-- The file explorer is about to open (Snacks.explorer(), <leader>e, cmd+b, …): hide the other sidebars
-- before it renders. Every way of opening it goes through Snacks.picker.pick.
vim.api.nvim_create_autocmd("VimEnter", {
  group = group,
  once = true,
  callback = function()
    if
      not (_G.Snacks and Snacks.picker and Snacks.picker.pick) or Snacks.picker._sidebars_wrapped
    then
      return
    end
    local pick = Snacks.picker.pick
    Snacks.picker.pick = function(source, opts)
      local name = type(source) == "table" and source.source or source
      local sidebar = name == "explorer" and "explorer" or name_of_source(name)
      if sidebar then
        if sidebar == "explorer" then
          require("core.leave-codediff").leave_graph()
        end
        local tab = vim.api.nvim_get_current_tabpage()
        M.make_room(sidebar, tab)
        local generation = M.generation(tab)
        local switch = switch_id
        local options =
          vim.tbl_extend("force", {}, type(source) == "table" and source or opts or {})
        local on_show = options.on_show
        options.on_show = function(picker)
          picker._sidebar_tab = tab
          if
            not vim.api.nvim_tabpage_is_valid(tab)
            or vim.api.nvim_get_current_tabpage() ~= tab
            or M.generation(tab) ~= generation
            or switch_id ~= switch
            or M.target(tab) ~= sidebar
          then
            close_now(picker)
            return
          end
          if on_show then
            on_show(picker)
          end
          M.reconcile()
        end
        local picker
        if type(source) == "table" then
          picker = pick(options)
        else
          picker = pick(source, options)
        end
        if picker then
          picker._sidebar_tab = tab
        end
        return picker
      end
      -- A search/recent-files popup is an explicit request too. A directory Explorer
      -- still waiting for its initial Git scan must not replace it when that scan finishes.
      M.request()
      return pick(source, opts)
    end
    Snacks.picker._sidebars_wrapped = true
  end,
})

return M
