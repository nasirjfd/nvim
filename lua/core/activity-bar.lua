-- VS Code-style activity bar: a 3-column strip on the far left of every tab with Explorer, Search
-- and Source Control icons. A click does what the key does (Cmd+Shift+E / F / G); hovering lights
-- the icon up and shows its name and key; the open view (explorer, git pane) is marked with a bar.
local M = {}

local api = vim.api
local ns = api.nvim_create_namespace("activity_bar")

-- Nerd Font codicons: files, search, source control
local ITEMS = {
  { icon = "\u{eaf0}", name = "Explorer", key = "⇧⌘E", lhs = "<D-S-e>" },
  { icon = "\u{ea6d}", name = "Search", key = "⇧⌘F", lhs = "<D-S-f>" },
  { icon = "\u{ea68}", name = "Source Control", key = "⇧⌘G", lhs = "<D-S-g>" },
}
local WIDTH = 3

local buf -- the bar's buffer (shared by the bar window of every tab)
local hovered -- index of the hovered item
local tip -- tooltip float

local function row_of(i)
  return 2 * i -- a blank line above each icon
end

local function item_at(line)
  for i in ipairs(ITEMS) do
    if row_of(i) == line then
      return i
    end
  end
end

local function set_highlights()
  local function get(name)
    return api.nvim_get_hl(0, { name = name, link = false })
  end
  local bg = get("SnacksPickerList").bg or get("NormalFloat").bg or get("Normal").bg
  local fg = get("Normal").fg
  local dim = get("Comment").fg or get("NonText").fg
  local accent = get("DiagnosticInfo").fg or get("Function").fg
  local function lighter(color, amount)
    if not color then
      return nil
    end
    local function ch(shift)
      local c = math.floor(color / shift) % 256
      return math.min(255, math.floor(c + (255 - c) * amount)) * shift
    end
    return ch(65536) + ch(256) + ch(1)
  end
  api.nvim_set_hl(0, "ActivityBar", { bg = bg, fg = dim })
  api.nvim_set_hl(0, "ActivityBarIcon", { bg = bg, fg = dim })
  api.nvim_set_hl(0, "ActivityBarActive", { bg = bg, fg = fg, bold = true })
  api.nvim_set_hl(0, "ActivityBarIndicator", { bg = bg, fg = accent })
  api.nvim_set_hl(0, "ActivityBarHover", { bg = lighter(bg, 0.08), fg = fg })
  api.nvim_set_hl(0, "ActivityBarTip", { bg = lighter(bg, 0.08), fg = fg })
  api.nvim_set_hl(0, "ActivityBarTipKey", { bg = lighter(bg, 0.08), fg = dim })
end

local function bar_win(tab)
  for _, win in ipairs(api.nvim_tabpage_list_wins(tab or 0)) do
    if api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
end

-- Which view is open in the current tab: "Explorer", "Source Control" or nil.
local function active()
  local tab = api.nvim_get_current_tabpage()
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  local panel = lifecycle and lifecycle.get_panel(tab)
  local view = lifecycle and lifecycle.get_panel_view(tab)
  local snacks = rawget(_G, "Snacks")
  if snacks and snacks.picker then
    for _, picker in ipairs(snacks.picker.get({ source = "explorer" })) do
      local w = picker.list and picker.list.win and picker.list.win.win
      if w and api.nvim_win_is_valid(w) and api.nvim_win_get_tabpage(w) == tab then
        return "Explorer"
      end
    end
  end
  if panel and panel.data and panel.data.kind == "scm" and not (view and view.is_hidden) then
    return "Source Control"
  end
end

local function render()
  if not (buf and api.nvim_buf_is_valid(buf)) then
    return
  end
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local open = active()
  for i, item in ipairs(ITEMS) do
    local row = row_of(i) - 1
    local group = (hovered == i and "ActivityBarHover")
      or (open == item.name and "ActivityBarActive")
      or "ActivityBarIcon"
    api.nvim_buf_set_extmark(
      buf,
      ns,
      row,
      0,
      { end_col = #api.nvim_buf_get_lines(buf, row, row + 1, false)[1], hl_group = group }
    )
    if open == item.name then
      api.nvim_buf_set_extmark(
        buf,
        ns,
        row,
        0,
        { virt_text = { { "▎", "ActivityBarIndicator" } }, virt_text_pos = "overlay" }
      )
    end
  end
end

local function close_tip()
  if tip and api.nvim_win_is_valid(tip) then
    pcall(api.nvim_win_close, tip, true)
  end
  tip = nil
end

local function show_tip(i)
  close_tip()
  local win = bar_win()
  if not win then
    return
  end
  local item = ITEMS[i]
  local text = " " .. item.name .. "  " .. item.key .. " "
  local tbuf = api.nvim_create_buf(false, true)
  vim.bo[tbuf].bufhidden = "wipe"
  api.nvim_buf_set_lines(tbuf, 0, -1, false, { text })
  api.nvim_buf_set_extmark(
    tbuf,
    ns,
    0,
    0,
    { end_col = #(" " .. item.name), hl_group = "ActivityBarTip" }
  )
  api.nvim_buf_set_extmark(
    tbuf,
    ns,
    0,
    #(" " .. item.name),
    { end_col = #text, hl_group = "ActivityBarTipKey" }
  )
  local pos = vim.fn.win_screenpos(win)
  tip = api.nvim_open_win(tbuf, false, {
    relative = "editor",
    row = pos[1] - 1 + row_of(i) - 1,
    col = pos[2] - 1 + WIDTH + 1,
    width = vim.fn.strdisplaywidth(text),
    height = 1,
    style = "minimal",
    focusable = false,
    zindex = 250,
    noautocmd = true,
  })
  vim.wo[tip].winhighlight = "NormalFloat:ActivityBarTip"
end

local function make_buf()
  buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "activitybar"
  local lines = {}
  for i, item in ipairs(ITEMS) do
    lines[row_of(i) - 1] = ""
    lines[row_of(i)] = " " .. item.icon .. " "
  end
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function style(win)
  local wo = vim.wo[win]
  wo.number, wo.relativenumber, wo.cursorline, wo.wrap, wo.list, wo.spell =
    false, false, false, false, false, false
  wo.signcolumn, wo.foldcolumn, wo.statuscolumn = "no", "0", ""
  wo.winfixwidth, wo.winfixbuf = true, true
  wo.fillchars = "eob: "
  wo.winhighlight = "Normal:ActivityBar,NormalNC:ActivityBar,EndOfBuffer:ActivityBar"
end

-- The bar is the leftmost window of the tab, over its whole height, WIDTH columns wide.
local function placed(win)
  local pos = vim.fn.win_screenpos(win)
  return pos[2] == 1
    and api.nvim_win_get_width(win) == WIDTH
    and #vim.fn.win_findbuf(buf) > 0
    and api.nvim_win_get_height(win) >= vim.o.lines - vim.o.cmdheight - 2
end

local busy = false
function M.ensure()
  if busy or vim.fn.getcmdwintype() ~= "" then
    return
  end
  busy = true
  pcall(function()
    if not (buf and api.nvim_buf_is_valid(buf)) then
      make_buf()
    end
    local win = bar_win()
    if not win then
      win = api.nvim_open_win(buf, false, { split = "left", win = -1, width = WIDTH })
      style(win)
    end
    if not placed(win) then
      api.nvim_win_call(win, function()
        vim.cmd("noautocmd wincmd H")
      end)
      api.nvim_win_set_width(win, WIDTH)
    end
    render()
  end)
  busy = false
end

local function schedule_ensure()
  vim.schedule(M.ensure)
end

-- Entering the bar (a click, or <C-w>h): go back where you were, and run the clicked item.
local function on_enter()
  local win = api.nvim_get_current_win()
  if api.nvim_win_get_buf(win) ~= buf then
    return
  end
  local pos = vim.fn.getmousepos()
  local clicked = pos.winid == win and item_at(pos.line) or nil
  vim.cmd("stopinsert")
  vim.cmd("wincmd p")
  if api.nvim_get_current_win() == win then
    vim.cmd("wincmd l")
  end
  if clicked then
    hovered = nil
    close_tip()
    vim.schedule(function()
      api.nvim_feedkeys(vim.keycode(ITEMS[clicked].lhs), "m", false)
    end)
  end
end

local function on_mouse_move()
  local pos = vim.fn.getmousepos()
  local win = bar_win()
  local now = (win and pos.winid == win) and item_at(pos.line) or nil
  if now ~= hovered then
    hovered = now
    render()
    if now then
      show_tip(now)
    else
      close_tip()
    end
  end
end

function M.setup()
  vim.o.mousemoveevent = true
  set_highlights()
  local group = api.nvim_create_augroup("ActivityBar", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })
  api.nvim_create_autocmd(
    { "VimEnter", "TabEnter", "TabNewEntered", "WinNew", "WinClosed", "VimResized" },
    {
      group = group,
      callback = schedule_ensure,
    }
  )
  -- an open / closed explorer or git pane changes the marker
  api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
    group = group,
    callback = function()
      vim.schedule(render)
    end,
  })
  api.nvim_create_autocmd("WinEnter", { group = group, callback = on_enter })
  -- :q in the last real window of a tab: take the bar away first, so the tab (or Neovim) closes
  api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      local current = api.nvim_get_current_win()
      local bar = bar_win()
      if not bar or bar == current then
        return
      end
      for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
        if win ~= current and win ~= bar and api.nvim_win_get_config(win).relative == "" then
          return
        end
      end
      busy = true -- don't put it back while quitting
      pcall(api.nvim_win_close, bar, true)
      vim.schedule(function()
        busy = false
      end)
    end,
  })
  vim.keymap.set(
    { "n", "i", "x", "s" },
    "<MouseMove>",
    on_mouse_move,
    { desc = "Activity bar hover" }
  )
  if vim.v.vim_did_enter == 1 then
    M.ensure()
  end
end

return M
