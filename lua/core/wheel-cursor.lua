-- Neovim requires its physical cursor to be visible. Keep the editing position separately
-- while the wheel moves the viewport; the next keyboard action resumes at that position.
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("WheelCursor")
local states = {}
local saved_cursor

local function restore(click)
  for win, state in pairs(states) do
    if api.nvim_win_is_valid(win) then
      if state.list then
        state.list.current = state.current
        state.list.render = state.render
        if not click then
          state.list:move(state.index, true)
        end
      elseif not click then
        pcall(api.nvim_win_set_cursor, win, state.cursor)
      end
      vim.wo[win].cursorline = state.cursorline
    end
    if api.nvim_buf_is_valid(state.buf) then
      api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
    end
  end
  states = {}
  if saved_cursor then
    vim.o.guicursor = saved_cursor
    saved_cursor = nil
  end
end

local function remember(win)
  if states[win] or not api.nvim_win_is_valid(win) then
    return
  end
  local buf = api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype == "terminal" then
    return
  end
  local state = {
    buf = buf,
    cursor = api.nvim_win_get_cursor(win),
    cursorline = vim.wo[win].cursorline,
  }
  states[win] = state
  if _G.Snacks and Snacks.picker then
    for _, picker in ipairs(Snacks.picker.get()) do
      local list = picker.list
      if list and list.win.win == win then
        state.list, state.index = list, list.cursor
        state.current, state.render = list.current, list.render
        -- Scrolling must not change the item used by actions or trigger a different preview.
        list.current = function(self)
          return self:get(state.index)
        end
        list.render = function(self)
          state.render(self)
          if not self.win:valid() then
            return
          end
          vim.wo[win].cursorline = false
          api.nvim_buf_clear_namespace(buf, ns, 0, -1)
          if state.index >= self.top and state.index < self.top + self:height() then
            api.nvim_buf_set_extmark(buf, ns, self:idx2row(state.index) - 1, 0, {
              line_hl_group = "SnacksPickerListCursorLine",
              priority = 200,
            })
          end
        end
        break
      end
    end
  end
  if not state.list then
    vim.wo[win].cursorline = false
    local line = api.nvim_buf_get_lines(buf, state.cursor[1] - 1, state.cursor[1], false)[1] or ""
    local col = math.min(state.cursor[2], #line)
    api.nvim_buf_set_extmark(buf, ns, state.cursor[1] - 1, col, {
      virt_text = { { vim.fn.strcharpart(line:sub(col + 1), 0, 1):gsub("^$", " "), "Cursor" } },
      virt_text_pos = "overlay",
      priority = 250,
    })
  end
  if not saved_cursor then
    saved_cursor = vim.o.guicursor
    api.nvim_set_hl(0, "WheelHiddenCursor", { blend = 100, nocombine = true })
    vim.o.guicursor = "a:WheelHiddenCursor"
  end
end

function M.setup()
  vim.on_key(function(key, typed)
    key = typed and typed ~= "" and typed or key
    local name = vim.fn.keytrans(key)
    if name:find("^<ScrollWheel") then
      -- Visual mode already has its own frozen-selection handling in core/keymaps.lua.
      if vim.fn.mode():match("^[vV\22]") or vim.o.guicursor:find("VisualScrollHiddenCursor", 1, true) then
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
