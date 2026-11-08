-- Every modal (a bordered floating window you are inside, big enough to be a dialog) gets a dark
-- backdrop behind it, so it stands out. Pickers and Lazy draw their own backdrop at the same
-- darkness; when one is already on screen nothing is added.
local M = {}

M.blend = 40 -- lower = darker

local api = vim.api
local backdrops = {} -- modal win -> backdrop win
local group = api.nvim_create_augroup("ModalBackdrop", { clear = true })

api.nvim_set_hl(0, "ModalBackdrop", { bg = "#000000", default = true })

local function is_backdrop(win)
  local cfg = api.nvim_win_get_config(win)
  return cfg.relative ~= ""
    and vim.wo[win].winblend > 0
    and cfg.width >= vim.o.columns - 1
    and cfg.height >= vim.o.lines - 3
end

local function backdrop_visible()
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if is_backdrop(win) then
      return true
    end
  end
  return false
end

local function is_modal(win)
  local cfg = api.nvim_win_get_config(win)
  if cfg.relative == "" or cfg.focusable == false or cfg.hide then
    return false
  end
  local border = cfg.border
  if not border or border == "none" or (type(border) == "table" and (border[1] == "" or border[1] == nil)) then
    return false
  end
  return cfg.width >= vim.o.columns * 0.3 and cfg.height >= vim.o.lines * 0.2
end

local function close(modal)
  local win = backdrops[modal]
  backdrops[modal] = nil
  if win and api.nvim_win_is_valid(win) then
    pcall(api.nvim_win_close, win, true)
  end
end

local function open(modal)
  if backdrops[modal] or backdrop_visible() then
    return
  end
  local zindex = api.nvim_win_get_config(modal).zindex or 50
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local win = api.nvim_open_win(buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = vim.o.lines,
    style = "minimal",
    focusable = false,
    border = "none",
    -- like the pickers: below the sidebar (zindex 30-33) so it isn't painted over
    zindex = math.max(1, math.min(zindex - 1, 20)),
    noautocmd = true,
  })
  vim.wo[win].winblend = M.blend
  vim.wo[win].winhighlight = "Normal:ModalBackdrop"
  backdrops[modal] = win
end

function M.setup()
  api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      vim.schedule(function()
        local win = api.nvim_get_current_win()
        if api.nvim_win_is_valid(win) and is_modal(win) then
          open(win)
        end
      end)
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      local win = tonumber(ev.match)
      if win and backdrops[win] then
        vim.schedule(function()
          close(win)
        end)
      end
    end,
  })
  api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      for _, win in pairs(backdrops) do
        if api.nvim_win_is_valid(win) then
          api.nvim_win_set_config(win, { relative = "editor", row = 0, col = 0, width = vim.o.columns, height = vim.o.lines })
        end
      end
    end,
  })
end

return M
