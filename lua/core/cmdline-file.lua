-- The file name at the left of the command line (the line `:q` and `:w` are typed on), hidden
-- while a command is being typed. Neovim has no slot there, so it is a one-row floating window
-- laid over the start of that row; the blame and line:col stay in the ruler on the right.
-- A message starts at the same spot, so the name stays hidden after a command until the cursor moves.
local M = {}

local buf, win, shown

local function ensure_buf()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "hide"
  end
  return buf
end

local function hide()
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_config, win, { hide = true })
  end
  shown = nil
end

-- Nothing in a diff view: the buffers there are virtual and the view has its own layout
local function in_diff()
  local session = package.loaded["codediff.ui.lifecycle.session"]
  return session ~= nil and session.get_active_diffs()[vim.api.nvim_get_current_tabpage()] ~= nil
end

local function render()
  if vim.fn.mode() == "c" or vim.fn.getcmdwintype() ~= "" then
    return hide()
  end
  if in_diff() then
    return hide()
  end
  local ok, text = pcall(_G.title_string)
  if not ok or not text or text == "" then
    return hide()
  end
  local width = vim.fn.strwidth(text) + 1
  local row = vim.o.lines - vim.o.cmdheight
  local key = text .. "|" .. width .. "|" .. row
  if shown == key and win and vim.api.nvim_win_is_valid(win) then
    return
  end
  local b = ensure_buf()
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { text })
  vim.api.nvim_buf_clear_namespace(b, -1, 0, -1)
  vim.api.nvim_buf_add_highlight(b, -1, "Comment", 0, 0, -1)
  local config = {
    relative = "editor",
    row = row,
    col = 0,
    width = math.min(width, math.floor(vim.o.columns / 2)),
    height = 1,
    style = "minimal",
    border = "none",
    focusable = false,
    zindex = 250,
    hide = false,
  }
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, config)
  else
    win = vim.api.nvim_open_win(b, false, config)
    vim.wo[win].winhighlight = "NormalFloat:Normal"
  end
  shown = key
end

function M.setup()
  local group = vim.api.nvim_create_augroup("CmdlineFile", { clear = true })
  -- Only events that can change the name or the row: nothing runs per cursor move or keystroke.
  vim.api.nvim_create_autocmd(
    { "BufEnter", "WinEnter", "TabEnter", "BufModifiedSet", "BufFilePost", "DirChanged", "VimResized", "InsertLeave" },
    { group = group, callback = vim.schedule_wrap(render) }
  )
  -- The diff view switches files without a buffer event of its own
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "CodeDiffOpen", "CodeDiffClose", "CodeDiffFileSelect" },
    callback = vim.schedule_wrap(render),
  })
  -- Esc out of the command line (nothing was run, so there is no message to read): the name is back at once
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = group,
    callback = function()
      if vim.v.event.abort then
        vim.defer_fn(function()
          shown = nil
          render()
        end, 30)
      end
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = group,
    callback = function()
      hide()
      -- Stay hidden after a command so its message ("written", an :echo) can be read; the first
      -- cursor move afterwards brings the name back, and the listener removes itself.
      vim.api.nvim_create_autocmd("CursorMoved", {
        group = group,
        once = true,
        callback = vim.schedule_wrap(render),
      })
    end,
  })
  vim.schedule(render)
end

M.setup()

return M
