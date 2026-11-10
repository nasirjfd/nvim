-- What the sidebar panes built on a Snacks picker (HTTP Requests, Tests) have in common.
local api = vim.api
local uv = vim.uv

local M = {}

local sources = {} -- picker source -> true, for every pane registered here

--- The panes of one source shown in `tab` (the current tab by default).
function M.panes(source, tab)
  tab = tab or api.nvim_get_current_tabpage()
  local found = {}
  if not _G.Snacks or not Snacks.picker then
    return found
  end
  for _, picker in ipairs(Snacks.picker.get({ source = source })) do
    local win = picker.list and picker.list.win and picker.list.win.win
    if win and api.nvim_win_is_valid(win) and api.nvim_win_get_tabpage(win) == tab then
      found[#found + 1] = picker
    end
  end
  return found
end

--- The title of the pane is the winbar of its window (the search box must not repeat it: give the picker
--- `title = ""`). Snacks sets the window options again when the layout updates, so call this on_show and
--- again after BufWinEnter (done for registered sources).
function M.set_title(picker, text)
  local layout = picker.layout
  local root = layout and not layout.closed and layout.root
  if root and root.win and api.nvim_win_is_valid(root.win) then
    local bar = "%#ExplorerTitle#%=" .. text .. "%="
    vim.wo[root.win].winbar = bar
    root.opts.wo = root.opts.wo or {}
    root.opts.wo.winbar = bar
  end
end

-- ── the terminal cursor ─────────────────────────────────────────────────────────────────────────
-- The rows are selected by the list's own highlight: the terminal cursor on top of it is only noise, so it
-- is hidden while a pane's list has the focus and given back when the focus leaves. One place does it for
-- all panes (two of them saving and restoring 'guicursor' would trip over each other).
local saved_guicursor ---@type string?

local function hide_cursor()
  if saved_guicursor == nil then
    saved_guicursor = vim.o.guicursor
    api.nvim_set_hl(0, "PaneHiddenCursor", { blend = 100, nocombine = true })
    vim.o.guicursor = "a:PaneHiddenCursor"
  end
end

local function show_cursor()
  if saved_guicursor ~= nil then
    vim.o.guicursor = saved_guicursor
    saved_guicursor = nil
  end
end

local function sync_cursor()
  local buf = api.nvim_get_current_buf()
  local in_pane = false
  if vim.bo[buf].filetype == "snacks_picker_list" then
    for source in pairs(sources) do
      for _, picker in ipairs(M.panes(source)) do
        in_pane = in_pane or picker.list.win.buf == buf
      end
    end
  end
  if in_pane then
    hide_cursor()
  else
    show_cursor()
  end
end

--- The guicursor that is in use while no pane hides it (for tests).
function M.hidden()
  return vim.o.guicursor == "a:PaneHiddenCursor"
end

-- ── mouse ───────────────────────────────────────────────────────────────────────────────────────
--- Snacks action for the press of a second quick click (a double click): the cursor goes onto the row like a
--- single press does; the release acts.
function M.press(picker)
  local mouse = vim.fn.getmousepos()
  local win = picker.list and picker.list.win and picker.list.win.win
  if win and mouse.winid == win and mouse.line > 0 then
    pcall(api.nvim_win_set_cursor, win, { mouse.line, 0 })
  end
end

--- A click on a row: the list has already moved its cursor there; run `action` on it (a click that ended
--- outside the list is ignored).
function M.click(picker, action)
  local mouse = vim.fn.getmousepos()
  local list_win = picker.list and picker.list.win and picker.list.win.win
  if mouse.winid ~= list_win then
    return
  end
  vim.schedule(function()
    if not picker.closed then
      picker:action(action)
    end
  end)
end

--- The keys that make mouse clicks act in a pane's list, for `win.list.keys`.
function M.mouse_keys(action_press, action_click)
  local keys = {}
  for _, n in ipairs({ "2", "3", "4" }) do
    keys["<" .. n .. "-LeftMouse>"] = action_press -- the release of every click acts
    keys["<" .. n .. "-LeftRelease>"] = action_click
  end
  keys["<LeftRelease>"] = action_click
  return keys
end

-- ── files ───────────────────────────────────────────────────────────────────────────────────────
-- A tab that shows a diff (codediff: the Git sidebar, a merge) must keep showing it: files are not opened
-- over its panes.
local function is_diff_tab(tab)
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  return lifecycle ~= nil and lifecycle.get_session(tab) ~= nil
end

--- The window a file is opened in: the one next to the pane; in a diff tab, a window of an ordinary tab
--- (a new tab when there is none).
function M.editing_window(picker)
  local win = picker.main
  local tab = picker.list and picker.list.win and picker.list.win.win and api.nvim_win_is_valid(picker.list.win.win)
    and api.nvim_win_get_tabpage(picker.list.win.win)
  if win and api.nvim_win_is_valid(win) and not (tab and is_diff_tab(tab)) then
    return win
  end
  for _, candidate in ipairs(api.nvim_list_tabpages()) do
    if not is_diff_tab(candidate) then
      api.nvim_set_current_tabpage(candidate)
      return api.nvim_get_current_win()
    end
  end
  vim.cmd("tabnew")
  return api.nvim_get_current_win()
end

--- Go to `line` of `file` in the editing window.
function M.goto_line(picker, file, line)
  local win = M.editing_window(picker)
  if not (win and api.nvim_win_is_valid(win)) then
    return false
  end
  api.nvim_set_current_win(win)
  if vim.fs.normalize(api.nvim_buf_get_name(0)) ~= vim.fs.normalize(file) then
    vim.cmd("edit " .. vim.fn.fnameescape(file))
  end
  pcall(api.nvim_win_set_cursor, 0, { math.min(line, api.nvim_buf_line_count(0)), 0 })
  vim.cmd("normal! zz")
  return true
end

-- ── the rows ────────────────────────────────────────────────────────────────────────────────────
function M.pad(text, width)
  local missing = width - vim.fn.strdisplaywidth(text)
  return missing > 0 and (text .. string.rep(" ", missing)) or text
end

--- Move the pane's cursor onto the row with this key.
function M.move_to(picker, key)
  for index, item in ipairs(picker:items()) do
    if item.key == key then
      picker.list:move(index, true)
      return true
    end
  end
  return false
end

--- Register a pane's source: its cursor is hidden while it has the focus and its title is drawn again
--- whenever Snacks lays its window out again.
---@param source string
---@param title string
function M.register(source, title)
  sources[source] = title
end

local group = api.nvim_create_augroup("PaneKit", { clear = true })
api.nvim_create_autocmd({ "BufEnter", "WinEnter", "WinLeave", "BufLeave", "FocusGained", "TabEnter", "ModeChanged" }, {
  group = group,
  callback = function()
    vim.schedule(sync_cursor)
  end,
})
api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    if vim.bo[args.buf].filetype ~= "snacks_picker_list" then
      return
    end
    vim.schedule(function()
      for source, title in pairs(sources) do
        for _, picker in ipairs(M.panes(source)) do
          M.set_title(picker, title)
        end
      end
    end)
  end,
})

return M
