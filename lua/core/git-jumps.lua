-- Keep Git layouts out of the window-local jumplist. An F4 departure adds one
-- layout-level return point without ever loading virtual diff buffers in an editor.
-- A gd/gr/… departure (leave_for_jump) opens the file elsewhere and then jumps: Ctrl+O from
-- where that jump landed goes straight back to the diff, not to the file the jump started from.
local M = {}
local api = vim.api
local returns = {}
local forward
local leaving_for_jump = false

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
    -- after a jump from the diff, the place it landed is one entry past the departure
    local back_home = mark.jump and index <= mark.index + 1
      or api.nvim_get_current_buf() == mark.buf and index <= mark.index
    if back_home then
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

--- In a diff pane: open the same file in an editor tab before a jump (gd, gr, …) so the jump
--- lands there; Ctrl+O from where it lands returns to the diff in one step.
function M.leave_for_jump()
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  if not (lifecycle and lifecycle.get_session(api.nvim_get_current_tabpage())) then
    return
  end
  leaving_for_jump = true
  local ok, err = pcall(require("codediff.ui.view.actions.panes").open_current_elsewhere)
  leaving_for_jump = false
  if not ok then
    error(err)
  end
end

function M.attach()
  local graph = require("codediff.ui.graph")
  if not graph._focus_commit_change then
    graph._focus_commit_change = true
    local bind_back = graph.bind_back
    graph.bind_back = function(...)
      bind_back(...)
      local session = require("codediff.ui.lifecycle").get_session(api.nvim_get_current_tabpage())
      -- Focus the modified pane before its asynchronous diff finishes loading.
      -- CodeDiff's jump_to_first_change then positions it at the first hunk,
      -- and F4 uses that cursor instead of the file list's default line 1.
      if
        session
        and session.back
        and session.modified_win
        and api.nvim_win_is_valid(session.modified_win)
      then
        api.nvim_set_current_win(session.modified_win)
      end
    end
  end
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
        jump = leaving_for_jump,
      }
      forward = nil
    end
  end
end

return M
