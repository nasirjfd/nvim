-- Match-case / whole-word / regex toggles for the grep picker (<leader>/): three small buttons at the
-- right end of the search box, clickable with a hover effect, also on <A-c> / <A-w> / <A-r>.
-- Defaults: case-insensitive, plain text (no regex), no whole-word.
local M = {}

local ns = vim.api.nvim_create_namespace("grep_toggles")
local BUTTONS = {
  { key = "case", label = " Aa ", tip = "Match case (A-c)" },
  { key = "word", label = " ab ", tip = "Whole word (A-w)" },
  { key = "regex", label = " .* ", tip = "Regex (A-r)" },
}
local GAP = " "
local TOTAL = 0
for _, b in ipairs(BUTTONS) do
  TOTAL = TOTAL + vim.fn.strdisplaywidth(b.label) + #GAP
end

local function set_hl()
  vim.api.nvim_set_hl(0, "GrepToggle", { fg = "#8a8f98", bg = "#2b2d33", default = true })
  vim.api.nvim_set_hl(0, "GrepToggleHover", { fg = "#e6e8ec", bg = "#44474f", default = true })
  vim.api.nvim_set_hl(0, "GrepToggleOn", { fg = "#ffffff", bg = "#3d6bb3", bold = true, default = true })
  vim.api.nvim_set_hl(0, "GrepToggleOnHover", { fg = "#ffffff", bg = "#5586d0", bold = true, default = true })
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
    local hl = on and (hover and "GrepToggleOnHover" or "GrepToggleOn") or (hover and "GrepToggleHover" or "GrepToggle")
    chunks[#chunks + 1] = { b.label, hl }
    chunks[#chunks + 1] = { GAP, "Normal" }
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, 0, 0, { virt_text = chunks, virt_text_pos = "right_align", hl_mode = "combine" })
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
    local w = vim.fn.strdisplaywidth(b.label)
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
