-- Like VS Code: while text is selected (on one line), every other occurrence of it in the window gets
-- a subtle highlight. Updates are debounced and only touch the match when the text really changes,
-- so it doesn't flicker while the selection grows.
local M = {}

local group = vim.api.nvim_create_augroup("SelectionHighlight", { clear = true })
local timer = assert(vim.uv.new_timer())
local DELAY = 80

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
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local id = vim.w[win].selection_match_id
  if id then
    pcall(vim.fn.matchdelete, id, win)
    vim.w[win].selection_match_id = nil
    vim.w[win].selection_match_pattern = nil
  end
end

-- the pattern for the current selection, or nil when nothing should be highlighted
local function current_pattern()
  if vim.fn.mode() ~= "v" then
    return nil
  end
  local start, finish = vim.fn.getpos("v"), vim.fn.getpos(".")
  if start[2] ~= finish[2] then
    return nil
  end
  local lines = vim.fn.getregion(start, finish, { type = "v" })
  local text = lines[1] or ""
  if #lines ~= 1 or vim.trim(text) == "" or vim.fn.strchars(text) < 2 then
    return nil
  end
  return "\\V" .. vim.fn.escape(text, "\\")
end

local function apply()
  local pattern = current_pattern()
  if not pattern then
    clear()
    return
  end
  if vim.w.selection_match_pattern == pattern then
    return
  end
  clear()
  vim.w.selection_match_id = vim.fn.matchadd("SelectionMatch", pattern, -1)
  vim.w.selection_match_pattern = pattern
end

local function schedule()
  timer:stop()
  timer:start(DELAY, 0, vim.schedule_wrap(apply))
end

function M.setup()
  set_highlight()
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlight })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    callback = function()
      if vim.fn.mode() == "v" then
        schedule()
      elseif vim.w.selection_match_id then
        timer:stop()
        clear()
      end
    end,
  })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function()
      if vim.fn.mode() == "v" then
        schedule()
      else
        timer:stop()
        clear()
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function()
      timer:stop()
      clear()
    end,
  })
end

return M
