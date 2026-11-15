-- Keep Git layouts out of the window-local jumplist. An F4 departure adds one
-- layout-level return point without ever loading virtual diff buffers in an editor.
local M = {}
local api = vim.api
local returns = {}
local forward

local function in_git()
  local tab = api.nvim_get_current_tabpage()
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  local graph = package.loaded["codediff.ui.graph"]
  return (lifecycle and (lifecycle.get_session(tab) or lifecycle.get_panel(tab)))
    or (graph and graph.get(tab))
end

local function jump(direction)
  if in_git() then
    return
  end
  local win = api.nvim_get_current_win()
  local mark = returns[win]
  if direction == "back" and mark then
    local index = vim.fn.getjumplist()[2]
    if api.nvim_get_current_buf() == mark.buf and index <= mark.index then
      returns[win] = nil
      if api.nvim_win_is_valid(mark.origin) then
        forward = { origin = mark.origin, editor = win }
        api.nvim_set_current_win(mark.origin)
        return
      end
    end
  end
  api.nvim_feedkeys(vim.keycode(direction == "back" and "<C-o>" or "<C-i>"), "nx", false)
end

function M.setup()
  vim.keymap.set("n", "<C-o>", function()
    for _ = 1, vim.v.count1 do
      jump("back")
    end
  end, { desc = "Jump back (whole Git view)" })
  vim.keymap.set("n", "<C-i>", function()
    for _ = 1, vim.v.count1 do
      jump("forward")
    end
  end, { desc = "Jump forward outside Git views" })
  vim.keymap.set("n", "<C-,>", function()
    if in_git() then
      if
        forward
        and api.nvim_get_current_win() == forward.origin
        and api.nvim_win_is_valid(forward.editor)
      then
        local origin, editor = forward.origin, forward.editor
        api.nvim_set_current_win(editor)
        returns[editor] =
          { origin = origin, buf = api.nvim_get_current_buf(), index = vim.fn.getjumplist()[2] }
        forward = nil
      end
      return
    end
    jump("forward")
  end, { desc = "Jump forward (whole Git view)" })
end

function M.attach()
  local panes = require("codediff.ui.view.actions.panes")
  if panes._layout_jumps then
    return
  end
  panes._layout_jumps = true
  local open = panes.open_in_prev_tab
  panes.open_in_prev_tab = function(ctx)
    local origin = api.nvim_get_current_win()
    open(ctx)
    if api.nvim_win_is_valid(origin) and api.nvim_get_current_tabpage() ~= ctx.tabpage then
      returns[api.nvim_get_current_win()] = {
        origin = origin,
        buf = api.nvim_get_current_buf(),
        index = vim.fn.getjumplist()[2],
      }
      forward = nil
    end
  end
end

return M
