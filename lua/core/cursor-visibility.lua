-- guicursor is global: sidebar and scrolling code must never save each other's hidden state.
local M = {}
local api = vim.api
local hidden_cursor = "a:PaneHiddenCursor,c-ci-cr:ver25"
local normal_cursor = vim.o.guicursor
local claims = {}
local focused_win = api.nvim_get_current_win()
local writing, scheduled, suspended = false, false, false
local navigation = {
  snacks_picker_list = true,
  ["codediff-explorer"] = true,
  ["codediff-history"] = true,
  ["codediff-graph"] = true,
  ["codediff-graph-details"] = true,
}

local function is_hidden(value)
  return value:find("HiddenCursor", 1, true) ~= nil
end

local function apply(value)
  if vim.o.guicursor ~= value then
    writing = true
    vim.o.guicursor = value
    writing = false
  end
end

function M.hidden()
  return vim.o.guicursor == hidden_cursor
end

function M.active(reason)
  return claims[reason] == focused_win
end

function M.sync()
  local current = vim.o.guicursor
  if not is_hidden(current) then
    normal_cursor = current
  end
  -- Background renderers temporarily enter windows with nvim_win_call. Their FileType/BufWinEnter
  -- events must not hide the global cursor over the editor that actually owns focus.
  local win = api.nvim_win_is_valid(focused_win) and focused_win or api.nvim_get_current_win()
  local hide = navigation[vim.bo[api.nvim_win_get_buf(win)].filetype] == true
  for reason, owner in pairs(claims) do
    if not api.nvim_win_is_valid(owner) then
      claims[reason] = nil
    elseif owner == win then
      hide = true
    end
  end
  if hide and not suspended then
    api.nvim_set_hl(0, "PaneHiddenCursor", { blend = 100, nocombine = true })
    apply(hidden_cursor)
  else
    apply(normal_cursor)
  end
end

function M.hide(reason, win)
  claims[reason] = win or api.nvim_get_current_win()
  M.sync()
end

function M.show(reason)
  claims[reason] = nil
  M.sync()
end

local function update()
  M.sync() -- restore immediately on entering an editor, not one event-loop turn later
  if scheduled then
    return
  end
  scheduled = true
  vim.schedule(function()
    scheduled = false
    M.sync() -- inspect current focus again after a picker has finished laying out its windows
  end)
end

function M.setup()
  local group = api.nvim_create_augroup("CursorVisibility", { clear = true })
  api.nvim_create_autocmd(
    {
      "WinEnter",
      "BufEnter",
      "BufWinEnter",
      "FileType",
      "TabEnter",
      "FocusGained",
      "ModeChanged",
      "ColorScheme",
    },
    {
      group = group,
      callback = function(event)
        if event.event == "WinEnter" or event.event == "TabEnter" then
          focused_win = api.nvim_get_current_win()
        end
        update()
      end,
    }
  )
  api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = "guicursor",
    callback = function()
      if not writing then
        update()
      end
    end,
  })
  api.nvim_create_autocmd({ "VimSuspend", "VimLeavePre" }, {
    group = group,
    callback = function()
      suspended = true
      apply(normal_cursor)
    end,
  })
  api.nvim_create_autocmd("VimResume", {
    group = group,
    callback = function()
      suspended = false
      update()
    end,
  })
  update()
end

return M
