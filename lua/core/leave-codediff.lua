-- A file opened from a picker (<leader><space>, Cmd+E, grep, LSP references, the explorer, …)
-- while in the git pane, or any other codediff tab, opens in a normal editor tab: the git pane is
-- left behind instead of having a pane replaced by the file. The git pane's tab stays alive in the
-- background (its list and file watcher keep running), so Cmd+Shift+G brings it back at once.
local M = {}

local api = vim.api

local function is_codediff_tab(tab)
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  if lifecycle and (lifecycle.get_session(tab) ~= nil or lifecycle.get_panel(tab) ~= nil) then
    return true
  end
  -- the git graph (with its commit details at the bottom)
  local graph = package.loaded["codediff.ui.graph"]
  return graph ~= nil and graph.get(tab) ~= nil
end

-- A plain window of a tab: its last used one, else the first that is not a float or a sidebar.
local function plain_window(tab)
  local function plain(win)
    local buf = api.nvim_win_get_buf(win)
    return api.nvim_win_get_config(win).relative == "" and vim.bo[buf].buftype == ""
  end
  local last = api.nvim_tabpage_get_win(tab)
  if plain(last) then
    return last
  end
  for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
    if plain(win) then
      return win
    end
  end
end

--- A window of a normal editor tab to open a file in, when `win` is in a codediff tab; nil otherwise.
--- Prefers the nearest tab before the codediff one; creates a first tab when there is none.
function M.editor_window(win)
  if not (win and api.nvim_win_is_valid(win)) then
    return nil
  end
  local tab = api.nvim_win_get_tabpage(win)
  if not is_codediff_tab(tab) then
    return nil
  end
  local tabs = api.nvim_list_tabpages()
  local index = vim.fn.index(tabs, tab) + 1
  local order = {}
  for i = index - 1, 1, -1 do
    order[#order + 1] = tabs[i]
  end
  for i = index + 1, #tabs do
    order[#order + 1] = tabs[i]
  end
  for _, other in ipairs(order) do
    if not is_codediff_tab(other) then
      local found = plain_window(other)
      if found then
        return found
      end
    end
  end
  vim.cmd("tabnew")
  vim.cmd("tabmove 0")
  return api.nvim_get_current_win()
end

-- Snacks opens a picker's file in the window the picker was started from (`picker.main`): point
-- that at an editor tab first.
function M.setup()
  local actions = require("snacks.picker.actions")
  if actions._leaves_codediff then
    return
  end
  actions._leaves_codediff = true
  local function wrap(fn)
    return function(picker, item, action)
      local target = M.editor_window(picker.main)
      if target then
        picker.main = target
      end
      return fn(picker, item, action)
    end
  end
  -- `confirm` (Enter) is the same function as `jump`, held separately
  local jump = actions.jump
  actions.jump = wrap(jump)
  if actions.confirm == jump then
    actions.confirm = actions.jump
  end
end

return M
