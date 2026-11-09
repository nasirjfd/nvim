-- Cursor-style activity bar: Explorer and Source Control icons in a row along the top of
-- the screen (Neovim's tab line). A click does what the key does (Cmd+Shift+E / G). Hovering
-- tints the icon and shows its name and key beside the icons; the open view is underlined.
local M = {}

local api = vim.api

-- Nerd Font codicons: files, source control
local ITEMS = {
  { icon = "\u{eaf0}", name = "Explorer", key = "⇧⌘E", lhs = "<D-S-e>" },
  { icon = "\u{ea68}", name = "Source Control", key = "⇧⌘G", lhs = "<D-S-g>" },
}
local LEFT = 1 -- columns before the first icon
local CELL = 5 -- each icon takes "  x  "

local hovered -- index of the icon under the mouse

local function set_highlights()
  local function get(name)
    return api.nvim_get_hl(0, { name = name, link = false })
  end
  local bg = get("SnacksPickerList").bg or get("NormalFloat").bg or get("Normal").bg
  local fg = get("Normal").fg
  local dim = get("Comment").fg or get("NonText").fg
  local accent = get("DiagnosticInfo").fg or get("Function").fg
  local hover_bg = bg
  if bg then
    local function ch(shift)
      local c = math.floor(bg / shift) % 256
      return math.min(255, c + 18) * shift
    end
    hover_bg = ch(65536) + ch(256) + ch(1)
  end
  api.nvim_set_hl(0, "ActivityBarFill", { bg = bg })
  api.nvim_set_hl(0, "ActivityBarIcon", { bg = bg, fg = dim })
  api.nvim_set_hl(0, "ActivityBarActive", { bg = bg, fg = fg, underline = true, sp = accent })
  api.nvim_set_hl(0, "ActivityBarHover", { bg = hover_bg, fg = fg })
  api.nvim_set_hl(0, "ActivityBarLabel", { bg = bg, fg = dim })
end

-- Which view is open in the current tab: "Explorer", "Source Control" or nil.
local function active()
  local tab = api.nvim_get_current_tabpage()
  local snacks = rawget(_G, "Snacks")
  if snacks and snacks.picker then
    for _, picker in ipairs(snacks.picker.get({ source = "explorer" })) do
      local w = picker.list and picker.list.win and picker.list.win.win
      if w and api.nvim_win_is_valid(w) and api.nvim_win_get_tabpage(w) == tab then
        return "Explorer"
      end
    end
  end
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  local panel = lifecycle and lifecycle.get_panel(tab)
  local view = lifecycle and lifecycle.get_panel_view(tab)
  if panel and panel.data and panel.data.kind == "scm" and not (view and view.is_hidden) then
    return "Source Control"
  end
end

function M.tabline()
  local ok, open = pcall(active)
  open = ok and open or nil
  local parts = { "%#ActivityBarFill#", string.rep(" ", LEFT) }
  for i, item in ipairs(ITEMS) do
    local group = (hovered == i and "ActivityBarHover")
      or (open == item.name and "ActivityBarActive")
      or "ActivityBarIcon"
    parts[#parts + 1] = ("%%%d@v:lua.ActivityBarClick@%%#%s#  %s  %%X"):format(i, group, item.icon)
  end
  parts[#parts + 1] = "%#ActivityBarLabel#"
  if hovered then
    local item = ITEMS[hovered]
    parts[#parts + 1] = "  " .. item.name .. "  " .. item.key
  end
  parts[#parts + 1] = "%#ActivityBarFill#%="
  return table.concat(parts)
end

function _G.ActivityBarClick(index)
  local item = ITEMS[index]
  if not item then
    return
  end
  vim.schedule(function()
    if vim.fn.mode():find("^[iR]") then
      vim.cmd("stopinsert")
    end
    api.nvim_feedkeys(vim.keycode(item.lhs), "m", false)
  end)
end

local function redraw()
  vim.cmd.redrawtabline()
end

local function on_mouse_move()
  local pos = vim.fn.getmousepos()
  local now
  if pos.screenrow == 1 and pos.winid == 0 then
    local i = math.floor((pos.screencol - 1 - LEFT) / CELL) + 1
    if pos.screencol > LEFT and ITEMS[i] then
      now = i
    end
  end
  if now ~= hovered then
    hovered = now
    redraw()
  end
end

function M.setup()
  vim.o.mousemoveevent = true
  vim.o.showtabline = 2
  vim.o.tabline = "%!v:lua.require'core.activity-bar'.tabline()"
  set_highlights()
  local group = api.nvim_create_augroup("ActivityBar", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })
  -- the explorer or git pane opening / closing moves the underline
  api.nvim_create_autocmd({ "TabEnter", "WinEnter", "WinClosed", "BufWinEnter" }, {
    group = group,
    callback = function()
      vim.schedule(redraw)
    end,
  })
  vim.keymap.set(
    { "n", "i", "x", "s" },
    "<MouseMove>",
    on_mouse_move,
    { desc = "Activity bar hover" }
  )
end

return M
