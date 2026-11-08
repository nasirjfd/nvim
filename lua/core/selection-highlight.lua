-- Like VS Code: while text is selected (on one line), every other occurrence of it in the window gets
-- a subtle highlight.
local M = {}

local group = vim.api.nvim_create_augroup("SelectionHighlight", { clear = true })

local function set_highlight()
  local function get(name)
    local ok, value = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
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
    vim.api.nvim_set_hl(0, "SelectionMatch", { bg = blend(visual.bg, normal.bg, 0.45), default = true })
  else
    vim.api.nvim_set_hl(0, "SelectionMatch", { link = "Search", default = true })
  end
end

local function clear(win)
  win = win or vim.api.nvim_get_current_win()
  local id = vim.w[win].selection_match_id
  if id then
    pcall(vim.fn.matchdelete, id, win)
    vim.w[win].selection_match_id = nil
  end
end

local function update()
  local mode = vim.fn.mode()
  if mode ~= "v" then
    clear()
    return
  end
  local start, finish = vim.fn.getpos("v"), vim.fn.getpos(".")
  -- only a selection inside one line, like VS Code
  if start[2] ~= finish[2] then
    clear()
    return
  end
  local lines = vim.fn.getregion(start, finish, { type = "v" })
  local text = lines[1] or ""
  if #lines ~= 1 or vim.trim(text) == "" or vim.fn.strchars(text) < 2 then
    clear()
    return
  end
  clear()
  local pattern = "\\V" .. vim.fn.escape(text, "\\")
  vim.w.selection_match_id = vim.fn.matchadd("SelectionMatch", pattern, -1)
end

function M.setup()
  set_highlight()
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlight })
  vim.api.nvim_create_autocmd({ "CursorMoved", "ModeChanged" }, {
    group = group,
    callback = function()
      update()
    end,
  })
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function()
      clear()
    end,
  })
end

return M
