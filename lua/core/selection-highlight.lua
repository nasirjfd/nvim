-- Like VS Code: while text is selected (on one line), the other occurrences of it on screen get a
-- subtle highlight. Only the visible lines are searched (plain find, extmarks), the selection itself
-- is never painted, and it updates in the same redraw as the selection, so nothing flickers.
-- Outside visual mode it costs one mode check per cursor move.
local M = {}

local api = vim.api
local ns = api.nvim_create_namespace("selection_highlight")
local group = api.nvim_create_augroup("SelectionHighlight", { clear = true })

local marked_buf, marked_key -- what is currently drawn

local function set_highlight()
  local function get(name)
    local ok, value = pcall(api.nvim_get_hl, 0, { name = name, link = false })
    return ok and value or {}
  end
  local visual, normal = get("Visual"), get("Normal")
  if visual.bg and normal.bg then
    local function blend(a, b, alpha)
      local function channel(shift)
        local x, y = math.floor(a / shift) % 256, math.floor(b / shift) % 256
        return math.floor(x * alpha + y * (1 - alpha) + 0.5) * shift
      end
      return channel(65536) + channel(256) + channel(1)
    end
    api.nvim_set_hl(0, "SelectionMatch", { bg = blend(visual.bg, normal.bg, 0.45), default = true })
  else
    api.nvim_set_hl(0, "SelectionMatch", { link = "Search", default = true })
  end
end

local function clear()
  if marked_buf then
    if api.nvim_buf_is_valid(marked_buf) then
      api.nvim_buf_clear_namespace(marked_buf, ns, 0, -1)
    end
    marked_buf, marked_key = nil, nil
  end
end

local function update()
  if api.nvim_get_mode().mode ~= "v" then
    return clear()
  end
  local s, e = vim.fn.getpos("v"), vim.fn.getpos(".")
  if s[2] ~= e[2] then
    return clear()
  end
  if s[3] > e[3] then
    s, e = e, s
  end
  local row = s[2] - 1
  local text = vim.fn.getregion(s, e, { type = "v" })[1] or ""
  if #text < 2 or not text:find("%S") then
    return clear()
  end
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local top, bottom = vim.fn.line("w0", win) - 1, vim.fn.line("w$", win)
  local key = table.concat({ buf, row, s[3], text, top, bottom, vim.b[buf].changedtick }, "\0")
  if key == marked_key then
    return
  end
  clear()
  local self_col = s[3] - 1
  local lines = api.nvim_buf_get_lines(buf, top, bottom, false)
  for i, line in ipairs(lines) do
    local lnum = top + i - 1
    local init = 1
    while true do
      local from, to = line:find(text, init, true)
      if not from then
        break
      end
      if not (lnum == row and from - 1 == self_col) then
        api.nvim_buf_set_extmark(buf, ns, lnum, from - 1, {
          end_col = to,
          hl_group = "SelectionMatch",
          priority = 90,
        })
      end
      init = to + 1
    end
  end
  marked_buf, marked_key = buf, key
end

function M.setup()
  set_highlight()
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlight })
  api.nvim_create_autocmd({ "CursorMoved", "WinScrolled", "TextChanged" }, {
    group = group,
    callback = function()
      if marked_buf or api.nvim_get_mode().mode == "v" then
        update()
      end
    end,
  })
  api.nvim_create_autocmd({ "ModeChanged", "WinLeave", "BufLeave" }, {
    group = group,
    callback = function(ev)
      if ev.event == "ModeChanged" and api.nvim_get_mode().mode == "v" then
        return update()
      end
      clear()
    end,
  })
end

return M
