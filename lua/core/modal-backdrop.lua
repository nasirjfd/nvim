-- Every modal (a bordered floating window you are inside, big enough to be a dialog) gets a dark
-- backdrop behind it, so it stands out. Pickers and Lazy draw their own backdrop at the same
-- darkness; when one is already on screen nothing is added.
local M = {}

M.blend = 40 -- lower = darker
M.sidebar_dim = 0.25 -- how much darker the explorer sidebar gets behind a modal (0..1)

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

local dimmed = {} -- sidebar win -> its winhighlight before dimming

local function blend(a, b, alpha)
  local function channel(shift)
    local x, y = math.floor(a / shift) % 256, math.floor(b / shift) % 256
    return math.floor(x * alpha + y * (1 - alpha) + 0.5) * shift
  end
  return channel(65536) + channel(256) + channel(1)
end

local function set_dim_highlights()
  local function get(name)
    local ok, value = pcall(api.nvim_get_hl, 0, { name = name, link = false })
    return ok and value or {}
  end
  local base = get("NormalFloat")
  local normal = get("Normal")
  local bg = base.bg or normal.bg or 0
  local fg = base.fg or normal.fg or 0xffffff
  local dark_bg = blend(bg, 0, 1 - M.sidebar_dim)
  api.nvim_set_hl(0, "ModalDim", { bg = dark_bg, fg = blend(fg, dark_bg, 1 - M.sidebar_dim * 0.6) })
  api.nvim_set_hl(0, "ModalDimText", { fg = blend(fg, dark_bg, 1 - M.sidebar_dim * 0.6) })
end

-- explorer sidebar parts: floats that sit above the backdrop but below modals
local function sidebar_wins()
  local wins = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local cfg = api.nvim_win_get_config(win)
    local ft = vim.bo[api.nvim_win_get_buf(win)].filetype
    if (cfg.relative ~= "" and cfg.zindex and cfg.zindex > 20 and cfg.zindex < 50 and not is_backdrop(win))
      or (cfg.relative == "" and ft == "snacks_layout_box") then
      wins[#wins + 1] = win
    end
  end
  return wins
end

local DIM_MAP = table.concat({
  "Normal:ModalDim",
  "NormalNC:ModalDim",
  "NormalFloat:ModalDim",
  "SnacksPickerList:ModalDim",
  "SnacksPickerInput:ModalDim",
  "SnacksPickerBox:ModalDim",
  "FloatBorder:ModalDim",
  "SnacksPickerFile:ModalDimText",
  "SnacksPickerDir:ModalDimText",
  "SnacksPickerDirectory:ModalDimText",
  "SnacksPickerTree:ModalDimText",
  "Directory:ModalDimText",
}, ",")

local function sync_dim()
  local want = backdrop_visible()
  if want then
    for _, win in ipairs(sidebar_wins()) do
      if dimmed[win] == nil then
        dimmed[win] = vim.wo[win].winhighlight
        local old = dimmed[win]
        vim.wo[win].winhighlight = old == "" and DIM_MAP or (old .. "," .. DIM_MAP)
      end
    end
  else
    for win, old in pairs(dimmed) do
      if api.nvim_win_is_valid(win) then
        vim.wo[win].winhighlight = old
      end
    end
    dimmed = {}
  end
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
    -- below the explorer sidebar (zindex 30-33): a blended window over another float wipes its
    -- text, so the sidebar is dimmed by dim_floats() instead
    zindex = math.max(1, math.min(zindex - 1, 20)),
    noautocmd = true,
  })
  vim.wo[win].winblend = M.blend
  vim.wo[win].winhighlight = "Normal:ModalBackdrop"
  backdrops[modal] = win
end

function M.setup()
  set_dim_highlights()
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_dim_highlights })
  api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      vim.schedule(function()
        local win = api.nvim_get_current_win()
        if api.nvim_win_is_valid(win) and is_modal(win) then
          open(win)
        end
        sync_dim()
      end)
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      local win = tonumber(ev.match)
      vim.schedule(function()
        if win and backdrops[win] then
          close(win)
        end
        sync_dim()
      end)
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
