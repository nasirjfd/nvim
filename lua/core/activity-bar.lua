-- Cursor-style switcher on top of the sidebar: Explorer and Source Control icons in the header row
-- (winbar) of the file explorer and of the git pane, as wide as the sidebar, shown only while one is
-- open. In the git pane they come before its own toolbar buttons. A click does what the key does
-- (Cmd+Shift+E / G), hovering tints the icon, the pane you are in is underlined.
local M = {}

local api = vim.api

-- Nerd Font codicons: files, source control
local ITEMS = {
  { icon = "\u{eaf0}", name = "Explorer", lhs = "<D-S-e>" },
  { icon = "\u{ea68}", name = "Source Control", lhs = "<D-S-g>" },
}
local LEFT = 1 -- columns before the first icon
local CELL = 3 -- each icon takes " x "

local hovered -- { win, index } of the icon under the mouse
local decorated = {} -- sidebar win -> { kind = "Explorer"|"Source Control", base = winbar after the icons }

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
  api.nvim_set_hl(0, "ActivityBarSep", { bg = bg, fg = dim })
end

local function icons(win, kind)
  local parts = { "%#ActivityBarFill#", string.rep(" ", LEFT) }
  for i, item in ipairs(ITEMS) do
    local is_hover = hovered and hovered[1] == win and hovered[2] == i
    local group = (is_hover and "ActivityBarHover")
      or (kind == item.name and "ActivityBarActive")
      or "ActivityBarIcon"
    parts[#parts + 1] = ("%%%d@v:lua.ActivityBarClick@%%#%s# %s %%X"):format(i, group, item.icon)
  end
  return table.concat(parts)
end

local function draw(win)
  local d = decorated[win]
  if not d or not api.nvim_win_is_valid(win) then
    decorated[win] = nil
    return
  end
  local rest = d.base ~= "" and ("%#ActivityBarSep#│" .. d.base) or "%#ActivityBarFill#%="
  local winbar = icons(win, d.kind) .. rest
  vim.wo[win].winbar = winbar
  -- snacks re-applies its window options when the explorer lays itself out: make it apply this
  if d.root and d.root.opts then
    d.root.opts.wo = d.root.opts.wo or {}
    d.root.opts.wo.winbar = winbar
  end
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

-- The explorer's header: on the window that holds its search box and list.
local function decorate_explorers()
  local snacks = rawget(_G, "Snacks")
  if not (snacks and snacks.picker) then
    return
  end
  for _, picker in ipairs(snacks.picker.get({ source = "explorer" })) do
    local win = picker.layout and picker.layout.root and picker.layout.root.win
    if win and api.nvim_win_is_valid(win) and (not decorated[win] or vim.wo[win].winbar == "") then
      decorated[win] = { kind = "Explorer", base = "", root = picker.layout.root }
      draw(win)
    end
  end
end

-- The git pane's toolbar is redrawn by codediff: put the icons back in front of it every time.
local function hook_git_toolbar()
  local ok, toolbar = pcall(require, "codediff.ui.explorer.toolbar")
  if not ok or toolbar._activity_bar then
    return
  end
  toolbar._activity_bar = true
  -- the icons and their separator: the toolbar leaves out buttons that would not fit beside them
  toolbar.reserved = LEFT + CELL * #ITEMS + 1
  local apply = toolbar.apply
  toolbar.apply = function(explorer, ...)
    local result = apply(explorer, ...)
    local win = explorer and explorer.winid
    if win and api.nvim_win_is_valid(win) and explorer.data and explorer.data.kind == "scm" then
      decorated[win] = { kind = "Source Control", base = vim.wo[win].winbar }
      draw(win)
    end
    return result
  end
end

M.hook_git_toolbar = hook_git_toolbar

local function on_mouse_move()
  local pos = vim.fn.getmousepos()
  local now
  if decorated[pos.winid] and pos.winrow == 1 then
    local i = math.floor((pos.wincol - 1 - LEFT) / CELL) + 1
    if pos.wincol > LEFT and ITEMS[i] then
      now = { pos.winid, i }
    end
  end
  local before = hovered
  if (now and now[1]) ~= (before and before[1]) or (now and now[2]) ~= (before and before[2]) then
    hovered = now
    for _, win in ipairs({ before and before[1] or false, now and now[1] or false }) do
      if win then
        draw(win)
      end
    end
  end
end

function M.setup()
  vim.o.mousemoveevent = true
  set_highlights()
  local group = api.nvim_create_augroup("ActivityBar", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })
  api.nvim_create_autocmd({ "WinNew", "WinEnter", "BufWinEnter", "TabEnter" }, {
    group = group,
    callback = function()
      vim.schedule(function()
        decorate_explorers()
        hook_git_toolbar()
      end)
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      decorated[tonumber(ev.match)] = nil
    end,
  })
  vim.keymap.set(
    { "n", "i", "x", "s" },
    "<MouseMove>",
    on_mouse_move,
    { desc = "Sidebar switcher hover" }
  )
end

return M
