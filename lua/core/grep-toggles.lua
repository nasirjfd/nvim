-- Match-case / whole-word / regex toggles for the grep picker (<leader>/): three small buttons at the
-- right end of the search box, clickable with a hover effect, also on <A-c> / <A-w> / <A-r>.
-- Defaults: case-insensitive, plain text (no regex), no whole-word.
local M = {}

local PRIORITY = 1
local ns = vim.api.nvim_create_namespace("grep_toggles")
local BUTTONS = {
  { key = "case", label = "Aa" },
  { key = "word", label = "ab" },
  { key = "regex", label = ".*" },
}
-- pill: rounded cap, " label ", rounded cap, then a gap
local CAP_L, CAP_R, GAP = "\u{e0b6}", "\u{e0b4}", " "
local function width_of(b)
  return vim.fn.strdisplaywidth(CAP_L .. " " .. b.label .. " " .. CAP_R)
end
local TOTAL = 0
for _, b in ipairs(BUTTONS) do
  TOTAL = TOTAL + width_of(b) + #GAP
end

local COLORS = {
  off = { fg = "#9aa0aa", bg = "#2e3138" },
  hover = { fg = "#ffffff", bg = "#4a4e58" },
  on = { fg = "#ffffff", bg = "#3d6bb3" },
  onhover = { fg = "#ffffff", bg = "#5a8ee0" },
}
local function set_hl()
  for name, c in pairs(COLORS) do
    vim.api.nvim_set_hl(0, "GrepToggle_" .. name, { fg = c.fg, bg = c.bg, bold = name:find("on") ~= nil, default = true })
    vim.api.nvim_set_hl(0, "GrepToggleCap_" .. name, { fg = c.bg, default = true })
  end
end

local function render(picker)
  local buf = picker.input and picker.input.win and picker.input.win.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local st = picker._toggles
  local chunks = {}
  for i, b in ipairs(BUTTONS) do
    local on, hover = st[b.key], st.hover == i
    local state = on and (hover and "onhover" or "on") or (hover and "hover" or "off")
    chunks[#chunks + 1] = { CAP_L, "GrepToggleCap_" .. state }
    chunks[#chunks + 1] = { " " .. b.label .. " ", "GrepToggle_" .. state }
    chunks[#chunks + 1] = { CAP_R, "GrepToggleCap_" .. state }
    chunks[#chunks + 1] = { GAP, "Normal" }
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, 0, 0, {
    virt_text = chunks, virt_text_pos = "right_align", hl_mode = "combine", priority = PRIORITY,
  })
end

local function apply(picker)
  local st = picker._toggles
  local args = { st.case and "--case-sensitive" or "--ignore-case" }
  if st.word then
    args[#args + 1] = "--word-regexp"
  end
  picker.opts.args = args
  picker.opts.regex = st.regex
  render(picker)
  picker:find({ refresh = true })
end

local function toggle(picker, key)
  picker._toggles[key] = not picker._toggles[key]
  apply(picker)
end

-- which button (1..3) is under the mouse, if the mouse is over the picker's input window
local function button_at(picker)
  local win = picker.input.win.win
  local m = vim.fn.getmousepos()
  if m.winid ~= win or m.line ~= 1 then
    return nil
  end
  local info = vim.fn.getwininfo(win)[1]
  local text_width = info.width - info.textoff
  local col = m.wincol - info.textoff - 1 -- 0-based inside the text area
  local x = text_width - TOTAL
  for i, b in ipairs(BUTTONS) do
    local w = width_of(b)
    if col >= x and col < x + w then
      return i
    end
    x = x + w + #GAP
  end
end

function M.attach(picker)
  set_hl()
  picker._toggles = { case = false, word = false, regex = false }
  picker.opts.args = { "--ignore-case" }
  picker.opts.regex = false
  local buf = picker.input.win.buf
  render(picker)

  local old_mousemove = vim.o.mousemoveevent
  vim.o.mousemoveevent = true
  local group = vim.api.nvim_create_augroup("GrepToggles" .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufEnter" }, { group = group, buffer = buf, callback = function() render(picker) end })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      vim.o.mousemoveevent = old_mousemove
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })

  local function map(lhs, fn, opts)
    vim.keymap.set({ "i", "n" }, lhs, fn, vim.tbl_extend("force", { buffer = buf, nowait = true }, opts or {}))
  end
  map("<LeftMouse>", function()
    local i = button_at(picker)
    if i then
      toggle(picker, BUTTONS[i].key)
      return ""
    end
    return "<LeftMouse>"
  end, { expr = true })
  map("<MouseMove>", function()
    local i = button_at(picker)
    if picker._toggles.hover ~= i then
      picker._toggles.hover = i
      render(picker)
    end
  end)
  map("<A-c>", function() toggle(picker, "case") end)
  map("<A-w>", function() toggle(picker, "word") end)
  map("<A-r>", function() toggle(picker, "regex") end)
end

return M
