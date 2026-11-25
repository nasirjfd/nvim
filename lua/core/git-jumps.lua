-- Keep whole Git layouts in history without loading virtual diff buffers in an editor.
-- An F4 departure adds a layout-level return point.
-- A gd/gr/… departure (leave_for_jump) opens the file elsewhere and then jumps: Ctrl+O from
-- where that jump landed goes straight back to the diff, not to the file the jump started from.
local M = {}
local api = vim.api
local returns = {}
local forward = {}
local origins = {}
local navigating = false
local leaving_for_jump = false

local function focus(win)
  navigating = true
  local ok, err = pcall(api.nvim_set_current_win, win)
  navigating = false
  if not ok then
    error(err)
  end
end

local function position(win)
  return api.nvim_win_call(win, function()
    return {
      win = win,
      buf = api.nvim_get_current_buf(),
      cursor = api.nvim_win_get_cursor(0),
      index = vim.fn.getjumplist()[2],
    }
  end)
end

local function restore(state)
  if not api.nvim_buf_is_valid(state.buf) then
    return
  end
  local offset = vim.fn.getjumplist()[2] - state.index
  if offset ~= 0 then
    vim.cmd.normal({
      args = { math.abs(offset) .. vim.keycode(offset > 0 and "<C-o>" or "<C-i>") },
      bang = true,
    })
  end
  api.nvim_win_set_buf(state.win, state.buf)
  local cursor = { math.min(state.cursor[1], api.nvim_buf_line_count(state.buf)), state.cursor[2] }
  api.nvim_win_set_cursor(state.win, cursor)
end

local function remember_forward(origin, editor)
  local state = position(origin)
  state.origin, state.editor = origin, editor
  state.destination = position(editor)
  forward[#forward + 1] = state
end

local function in_git()
  local tab = api.nvim_get_current_tabpage()
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  local graph = package.loaded["codediff.ui.graph"]
  return (lifecycle and (lifecycle.get_session(tab) or lifecycle.get_panel(tab)))
    or (graph and graph.get(tab))
end

local function jump(direction)
  local win = api.nvim_get_current_win()
  local next_view = forward[#forward]
  if direction == "forward" and next_view and next_view.origin == win then
    if
      in_git()
      or api.nvim_get_current_buf() == next_view.buf
        and vim.fn.getjumplist()[2] >= next_view.index
    then
      table.remove(forward)
      if api.nvim_win_is_valid(next_view.editor) then
        local from_git = in_git()
        focus(next_view.editor)
        if not in_git() then
          restore(next_view.destination)
        end
        if from_git and not in_git() then
          returns[next_view.editor] =
            { origin = win, buf = api.nvim_get_current_buf(), index = vim.fn.getjumplist()[2] }
        end
        return
      end
    end
  end
  if in_git() then
    local origin = origins[api.nvim_get_current_tabpage()]
    if direction == "back" and origin and api.nvim_win_is_valid(origin.win) then
      focus(origin.win)
      if not in_git() then
        restore(origin)
        returns[origin.win] = nil
      end
      remember_forward(origin.win, win)
    end
    return
  end
  local mark = returns[win]
  if direction == "back" and mark then
    local index = vim.fn.getjumplist()[2]
    -- after a jump from the diff, the place it landed is one entry past the departure
    local back_home = mark.jump and index <= mark.index + 1
      or api.nvim_get_current_buf() == mark.buf and index <= mark.index
    if back_home then
      returns[win] = nil
      if api.nvim_win_is_valid(mark.origin) then
        remember_forward(mark.origin, win)
        focus(mark.origin)
        return
      end
    end
  end
  api.nvim_feedkeys(vim.keycode(direction == "back" and "<C-o>" or "<C-i>"), "nx", false)
end

function M.setup()
  local previous
  local group = api.nvim_create_augroup("GitLayoutHistory", { clear = true })
  api.nvim_create_autocmd("TabLeave", {
    group = group,
    callback = function()
      if not navigating then
        previous = position(api.nvim_get_current_win())
      end
    end,
  })
  api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = function()
      if not navigating and previous then
        origins[api.nvim_get_current_tabpage()] = previous
        forward = {}
      end
    end,
  })
  vim.keymap.set("n", "<C-o>", function()
    for _ = 1, vim.v.count1 do
      jump("back")
    end
  end, { desc = "Jump back (whole Git view)" })
  vim.keymap.set("n", "<C-i>", function()
    for _ = 1, vim.v.count1 do
      jump("forward")
    end
  end, { desc = "Jump forward (whole Git view)" })
  vim.keymap.set("n", "<C-,>", function()
    for _ = 1, vim.v.count1 do
      jump("forward")
    end
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
      forward = {}
    end
  end
end

return M
