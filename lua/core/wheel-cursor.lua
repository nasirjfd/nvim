-- Neovim requires its physical cursor to be visible. Keep the editing position separately
-- while the wheel moves the viewport; the next keyboard action resumes at that position.
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("WheelCursor")
local states = {}
local visibility = require("core.cursor-visibility")

local function restore(click)
  for win, state in pairs(states) do
    if api.nvim_win_is_valid(win) then
      if not click then
        pcall(api.nvim_win_set_cursor, win, state.cursor)
      end
      vim.wo[win].cursorline = state.cursorline
    end
    if api.nvim_buf_is_valid(state.buf) then
      api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
    end
  end
  states = {}
  visibility.show("wheel")
end

local function remember(win)
  if states[win] or not api.nvim_win_is_valid(win) then
    return
  end
  local buf = api.nvim_win_get_buf(win)
  -- Picker cursors are selections, not editing positions. Snacks owns their wheel handling;
  -- freezing current()/render() here splits the visible cursor from the selected item/preview.
  if vim.bo[buf].buftype == "terminal" or vim.bo[buf].filetype == "snacks_picker_list" then
    return
  end
  local state = {
    buf = buf,
    cursor = api.nvim_win_get_cursor(win),
    cursorline = vim.wo[win].cursorline,
  }
  states[win] = state
  vim.wo[win].cursorline = false
  local line = api.nvim_buf_get_lines(buf, state.cursor[1] - 1, state.cursor[1], false)[1] or ""
  local col = math.min(state.cursor[2], #line)
  api.nvim_buf_set_extmark(buf, ns, state.cursor[1] - 1, col, {
    virt_text = { { vim.fn.strcharpart(line:sub(col + 1), 0, 1):gsub("^$", " "), "Cursor" } },
    virt_text_pos = "overlay",
    priority = 250,
  })
  visibility.hide("wheel", win)
end

function M.setup()
  api.nvim_create_autocmd({ "WinLeave", "BufLeave", "TabLeave" }, {
    group = api.nvim_create_augroup("WheelCursorFocus", { clear = true }),
    callback = function()
      if next(states) then
        restore(true)
      end
    end,
  })
  vim.on_key(function(key, typed)
    key = typed and typed ~= "" and typed or key
    local name = vim.fn.keytrans(key)
    if name:find("^<ScrollWheel") then
      -- Visual mode already has its own frozen-selection handling in core/keymaps.lua.
      if vim.fn.mode():match("^[vV\22]") or visibility.active("visual-scroll") then
        return
      end
      local win = vim.fn.getmousepos().winid
      if win ~= 0 then
        remember(win)
      end
    elseif not name:find("^<MouseMove") and next(states) then
      restore(name:find("Mouse") ~= nil or name:find("Release") ~= nil)
    end
  end, ns)
end

return M
