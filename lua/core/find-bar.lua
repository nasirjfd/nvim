-- JetBrains-style find / replace bar at the top right of the window, instead of Vim's search line.
--
--   /  or Cmd+F   find                 Cmd+R   find and replace (Cmd+R twice: LSP rename)
--
-- Typing searches as you go and jumps to the first match from the cursor (or, when that one is out of
-- sight and there is a match on the screen, to the first match on the screen). The buttons on the
-- right toggle Match case (Aa), Words (W) and Regex (.*); they can be clicked, or toggled with
-- Option+C / Option+W / Option+X like in JetBrains. The chevron on the left (or Cmd+R) shows the
-- replace field, with Replace and Replace All buttons (Option+P / Option+A).
--
-- In the bar: Enter / Down next match, Shift+Enter / Up previous, Tab switches between the find
-- and replace fields, Esc closes. The bar stays open while you click or select in the file; Esc
-- there (with nothing selected) closes it. A selection is put in the find field. The text is searched
-- literally unless Regex is on (then it is a regex with $1 for groups in the replacement).
-- After closing, n / N go on with the same search.
local M = {}

local api = vim.api
local ns = api.nvim_create_namespace("find_bar")
local ui_ns = api.nvim_create_namespace("find_bar_ui")

-- remembered between uses
local opts = { case = false, word = false, regex = false }
local last = { find = "", replace = "" }

local state -- the open bar: { win, buf, target, tbuf, origin, replace, buttons, opened_at, by_r }

local function set_highlights()
  local function link(name, to)
    api.nvim_set_hl(0, name, { link = to, default = true })
  end
  link("FindBarOff", "Comment")
  link("FindBarOn", "PmenuSel")
  link("FindBarAction", "Special")
  link("FindBarCount", "Comment")
  link("FindBarNoMatch", "DiagnosticError")
  link("FindBarChevron", "Special")
  link("FindBarCurrent", "CurSearch")
end
set_highlights()
api.nvim_create_autocmd("ColorScheme", { callback = set_highlights })

-- The Vim pattern for the text and the toggles, or nil for an empty text.
local function pattern(text)
  if text == "" then
    return nil
  end
  local case = opts.case and "\\C" or "\\c"
  if opts.regex then
    local body = opts.word and ("<(" .. text .. ")>") or text
    return case .. "\\v" .. body
  end
  local body = text:gsub("\\", "\\\\")
  if opts.word then
    body = "\\<" .. body .. "\\>"
  end
  return case .. "\\V" .. body
end

local function valid(pat)
  return pcall(vim.regex, pat)
end

local function alive()
  return state and api.nvim_win_is_valid(state.win) and api.nvim_win_is_valid(state.target)
end

local function fields()
  local lines = api.nvim_buf_get_lines(state.buf, 0, -1, false)
  return lines[1] or "", lines[2] or ""
end

-- Where the match at (lnum, col) ends: exclusive end column (0-based) on its last line.
local function match_end(pat, lnum, col)
  local e = api.nvim_win_call(state.target, function() -- returns only one value: a table
    local view = vim.fn.winsaveview()
    api.nvim_win_set_cursor(0, { lnum, col - 1 })
    local e = vim.fn.searchpos(pat, "cneW")
    vim.fn.winrestview(view)
    if e[1] == 0 then
      return { lnum, col - 1 }
    end
    local line = api.nvim_buf_get_lines(state.tbuf, e[1] - 1, e[1], false)[1] or ""
    local char = vim.fn.strpart(line, e[2] - 1, 1, 1)
    return { e[1], e[2] - 1 + math.max(#char, 1) }
  end)
  return e[1], e[2]
end

-- The match the cursor of the target window is on, as { lnum, col (1-based), elnum, ecol (excl.) }
local function current_match(pat)
  local cur = api.nvim_win_get_cursor(state.target)
  local at = api.nvim_win_call(state.target, function()
    return vim.fn.searchpos(pat, "cnW", cur[1])
  end)
  if at[1] ~= cur[1] or at[2] ~= cur[2] + 1 then
    return nil
  end
  local el, ec = match_end(pat, at[1], at[2])
  return { at[1], at[2], el, ec }
end

-- Buttons drawn right-aligned on a line of the bar: { label, hl, action }
local function draw()
  local find = fields()
  local pat = pattern(find)
  api.nvim_buf_clear_namespace(state.buf, ui_ns, 0, -1)
  state.buttons = {}

  local function toggle(label, key)
    return {
      " " .. label .. " ",
      opts[key] and "FindBarOn" or "FindBarOff",
      function()
        opts[key] = not opts[key]
        M.update(true)
      end,
    }
  end

  local count_chunk
  if not pat then
    count_chunk = { "", "FindBarCount" }
  elseif not valid(pat) then
    count_chunk = { "bad regex", "FindBarNoMatch" }
  else
    local ok, sc = pcall(api.nvim_win_call, state.target, function()
      return vim.fn.searchcount({ pattern = pat, recompute = true, maxcount = 99999, timeout = 300 })
    end)
    if not ok or sc.total == 0 then
      count_chunk = { "0 results", "FindBarNoMatch" }
    else
      local current = current_match(pat) and sc.current or "?"
      count_chunk = { ("%s/%d"):format(current, sc.total), "FindBarCount" }
    end
  end

  local rows = {
    {
      { count_chunk[1] .. "  ", count_chunk[2] },
      toggle("Aa", "case"),
      toggle("W", "word"),
      toggle(".*", "regex"),
      { "  ", "FindBarOff" },
      {
        " ↑ ",
        "FindBarAction",
        function()
          M.step(-1)
        end,
      },
      {
        " ↓ ",
        "FindBarAction",
        function()
          M.step(1)
        end,
      },
      { " ✕ ", "FindBarOff", M.close },
    },
  }
  if state.replace then
    rows[2] = {
      { " Replace ", "FindBarAction", M.replace_one },
      { " ", "FindBarOff" },
      { " Replace All ", "FindBarAction", M.replace_all },
    }
  end

  local text_width = api.nvim_win_get_width(state.win) - 2 -- the sign column holds the chevron
  for row, chunks in ipairs(rows) do
    local total = 0
    for _, c in ipairs(chunks) do
      total = total + vim.fn.strdisplaywidth(c[1])
    end
    local col = text_width - total + 1
    local virt = {}
    for _, c in ipairs(chunks) do
      local w = vim.fn.strdisplaywidth(c[1])
      if c[3] then
        state.buttons[#state.buttons + 1] =
          { row = row, from = col, to = col + w - 1, action = c[3] }
      end
      virt[#virt + 1] = { c[1], c[2] }
      col = col + w
    end
    api.nvim_buf_set_extmark(
      state.buf,
      ui_ns,
      row - 1,
      0,
      { virt_text = virt, virt_text_pos = "right_align" }
    )
  end
  api.nvim_buf_set_extmark(state.buf, ui_ns, 0, 0, {
    sign_text = state.replace and "" or "",
    sign_hl_group = "FindBarChevron",
  })
end

-- Mark the match under the target's cursor, scroll it into view (below the bar).
local function show_current(pat, scroll)
  api.nvim_buf_clear_namespace(state.tbuf, ns, 0, -1)
  local m = pat and current_match(pat)
  if not m then
    return
  end
  api.nvim_buf_set_extmark(state.tbuf, ns, m[1] - 1, m[2] - 1, {
    end_row = m[3] - 1,
    end_col = m[4],
    hl_group = "FindBarCurrent",
    priority = 300,
  })
  if scroll == false then
    return
  end
  api.nvim_win_call(state.target, function()
    local top, bottom = vim.fn.line("w0"), vim.fn.line("w$")
    local bar_rows = (state.replace and 2 or 1) + 2
    if m[1] < top + bar_rows or m[1] > bottom then
      vim.cmd("normal! zz")
    end
  end)
end

-- The first and last line shown in the current window.
local function visible_lines()
  return vim.fn.line("w0"), vim.fn.line("w$")
end

-- Put the cursor on the match to show first: the first one from the cursor, but when that one is out
-- of sight and a match is on the screen, the first on the screen. So searching does not throw you to
-- the top (or the bottom) of the file while what you look for is right here. Runs in the target window.
local function first_match(pat)
  -- (read before the cursor moves: line("w0") scrolls the window to the cursor first)
  local top, bottom = visible_lines()
  local r = vim.fn.searchpos(pat, "cw")
  if r[1] == 0 then
    return
  end
  if r[1] >= top and r[1] <= bottom then
    return
  end
  api.nvim_win_set_cursor(0, { top, 0 })
  local seen = vim.fn.searchpos(pat, "cW")
  if seen[1] == 0 or seen[1] > bottom then
    api.nvim_win_set_cursor(0, { r[1], r[2] - 1 }) -- nothing on the screen: where the search went
  end
end

-- Search again after the text or a toggle changed: from where the search started.
function M.update(from_origin)
  if not alive() then
    return
  end
  local find, replace = fields()
  last.find, last.replace = find, state.replace and replace or last.replace
  local pat = pattern(find)
  if not pat or not valid(pat) then
    vim.v.hlsearch = 0
    api.nvim_buf_clear_namespace(state.tbuf, ns, 0, -1)
    if from_origin then
      api.nvim_win_set_cursor(state.target, state.origin)
    end
    draw()
    return
  end
  vim.fn.setreg("/", pat)
  vim.v.hlsearch = 1
  if from_origin then
    api.nvim_win_call(state.target, function()
      api.nvim_win_set_cursor(0, state.origin)
      first_match(pat)
    end)
  end
  show_current(pat)
  draw()
end

-- Next (1) or previous (-1) match; typing then goes on from there.
function M.step(dir)
  if not alive() then
    return
  end
  local pat = pattern((fields()))
  if not pat or not valid(pat) then
    return
  end
  api.nvim_win_call(state.target, function()
    vim.fn.searchpos(pat, dir > 0 and "w" or "bw")
  end)
  state.origin = api.nvim_win_get_cursor(state.target)
  M.update(false)
end

-- The text a match is replaced with: the replace field as it is, or with $1… groups for a regex.
local function replacement(pat, matched, text)
  if not opts.regex then
    return text
  end
  local sub = text:gsub("\\", "\\\\"):gsub("&", "\\&"):gsub("~", "\\~"):gsub("%$(%d)", "\\%1")
  return vim.fn.substitute(matched, pat, sub, "")
end

local function replace_range(m, pat, text)
  local lines = api.nvim_buf_get_text(state.tbuf, m[1] - 1, m[2] - 1, m[3] - 1, m[4], {})
  local new = replacement(pat, table.concat(lines, "\n"), text)
  local new_lines = vim.split(new, "\n", { plain = true })
  api.nvim_buf_set_text(state.tbuf, m[1] - 1, m[2] - 1, m[3] - 1, m[4], new_lines)
  local end_line = m[1] + #new_lines - 1
  local end_col = (#new_lines == 1 and (m[2] - 1) or 0) + #new_lines[#new_lines]
  return end_line, end_col
end

local function writable()
  if not vim.bo[state.tbuf].modifiable or vim.bo[state.tbuf].readonly then
    vim.notify("This buffer can't be changed", vim.log.levels.WARN)
    return false
  end
  return true
end

-- Replace the match under the cursor and go to the next one (or just go to the next one).
function M.replace_one()
  if not alive() or not writable() then
    return
  end
  local find, text = fields()
  local pat = pattern(find)
  if not pat or not valid(pat) then
    return
  end
  local m = current_match(pat)
  if m then
    local el, ec = replace_range(m, pat, text)
    api.nvim_win_set_cursor(state.target, { el, ec })
    api.nvim_win_call(state.target, function()
      vim.fn.searchpos(pat, "cw")
    end)
  else
    api.nvim_win_call(state.target, function()
      vim.fn.searchpos(pat, "w")
    end)
  end
  state.origin = api.nvim_win_get_cursor(state.target)
  M.update(false)
end

-- Replace every match in the buffer (one undo step).
function M.replace_all()
  if not alive() or not writable() then
    return
  end
  local find, text = fields()
  local pat = pattern(find)
  if not pat or not valid(pat) then
    return
  end
  local matches = {}
  api.nvim_win_call(state.target, function()
    local view = vim.fn.winsaveview()
    api.nvim_win_set_cursor(0, { 1, 0 })
    local flags = "cW"
    while true do
      local at = vim.fn.searchpos(pat, flags)
      if at[1] == 0 then
        break
      end
      local el, ec = match_end(pat, at[1], at[2])
      local prev = matches[#matches]
      if prev and prev[1] == at[1] and prev[2] == at[2] then
        break
      end
      matches[#matches + 1] = { at[1], at[2], el, ec }
      -- go on after the match (an empty match: one character further)
      if el == at[1] and ec <= at[2] - 1 then
        flags = "W"
      else
        api.nvim_win_set_cursor(0, { el, math.max(ec - 1, 0) })
        flags = "W"
      end
    end
    vim.fn.winrestview(view)
  end)
  for i = #matches, 1, -1 do
    replace_range(matches[i], pat, text)
  end
  vim.notify(("Replaced %d occurrence%s"):format(#matches, #matches == 1 and "" or "s"))
  M.update(false)
end

function M.close()
  if not state then
    return
  end
  local s = state
  state = nil
  if api.nvim_buf_is_valid(s.tbuf) then
    api.nvim_buf_clear_namespace(s.tbuf, ns, 0, -1)
  end
  vim.v.hlsearch = 0
  local in_bar = api.nvim_get_current_win() == s.win
  pcall(api.nvim_del_augroup_by_name, "FindBar")
  for _, mode in ipairs({ "n", "x", "i" }) do
    pcall(vim.keymap.del, mode, "<LeftMouse>")
  end
  if api.nvim_win_is_valid(s.win) then
    pcall(api.nvim_win_close, s.win, true)
  end
  if in_bar then
    if api.nvim_win_is_valid(s.target) then
      api.nvim_set_current_win(s.target)
    end
    vim.cmd("stopinsert")
  end
end

function M.is_open()
  return alive() == true
end

-- Where the bar sits: the top right corner of the window it searches.
local function geometry(target, height)
  local tw = api.nvim_win_get_width(target)
  return {
    relative = "win",
    win = target,
    anchor = "NE",
    row = 0,
    col = tw,
    width = math.max(math.min(72, tw - 2), 20),
    height = height,
  }
end

local function resize()
  api.nvim_win_set_config(state.win, geometry(state.target, state.replace and 2 or 1))
end

local function show_replace(on)
  state.replace = on
  local lines = api.nvim_buf_get_lines(state.buf, 0, -1, false)
  if on and #lines < 2 then
    api.nvim_buf_set_lines(state.buf, 1, -1, false, { last.replace })
  elseif not on and #lines > 1 then
    last.replace = lines[2]
    api.nvim_buf_set_lines(state.buf, 1, -1, false, {})
  end
  resize()
  local row = on and 2 or 1
  local line = api.nvim_buf_get_lines(state.buf, row - 1, row, false)[1] or ""
  api.nvim_win_set_cursor(state.win, { row, #line })
  M.update(false)
end

-- A click on the bar: a button runs, elsewhere the cursor moves there. A click outside it is an
-- ordinary click: the bar stays open (Esc closes it).
local function click()
  local pos = vim.fn.getmousepos()
  if pos.winid ~= state.win then
    api.nvim_feedkeys(vim.keycode("<LeftMouse>"), "n", false)
    return
  end
  if api.nvim_get_current_win() ~= state.win then
    api.nvim_set_current_win(state.win)
  end
  -- a click on the frame around the bar: line 0 (top border) or past the last line (bottom border)
  pos.line = math.min(math.max(pos.line, 1), api.nvim_buf_line_count(state.buf))
  pos.column = math.max(pos.column, 1)
  if pos.line == 1 and pos.wincol <= 2 then
    show_replace(not state.replace)
    return
  end
  local col = pos.wincol - 2
  for _, b in ipairs(state.buttons) do
    if b.row == pos.line and col >= b.from and col <= b.to then
      b.action()
      return
    end
  end
  local line = api.nvim_buf_get_lines(state.buf, pos.line - 1, pos.line, false)[1] or ""
  api.nvim_win_set_cursor(state.win, { pos.line, math.min(math.max(pos.column - 1, 0), #line) })
end

local function keymaps(buf)
  local function map(lhs, fn, modes)
    vim.keymap.set(modes or { "i", "n" }, lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  local function row()
    return api.nvim_win_get_cursor(state.win)[1]
  end
  map("<Esc>", M.close)
  map("<C-c>", M.close)
  map("<CR>", function()
    if row() == 2 then
      M.replace_one()
    else
      M.step(1)
    end
  end)
  map("<S-CR>", function()
    M.step(-1)
  end)
  map("<Down>", function()
    M.step(1)
  end)
  map("<Up>", function()
    M.step(-1)
  end)
  map("<Tab>", function()
    if state.replace then
      local r = row() == 1 and 2 or 1
      local line = api.nvim_buf_get_lines(state.buf, r - 1, r, false)[1] or ""
      api.nvim_win_set_cursor(state.win, { r, #line })
    end
  end)
  map("<S-Tab>", function()
    if state.replace then
      local r = row() == 1 and 2 or 1
      local line = api.nvim_buf_get_lines(state.buf, r - 1, r, false)[1] or ""
      api.nvim_win_set_cursor(state.win, { r, #line })
    end
  end)
  -- Option+C / W / X / P / A: Alt with "Option as Alt", the typed character without it (US layout)
  local function toggle(key)
    return function()
      opts[key] = not opts[key]
      M.update(true)
    end
  end
  for _, lhs in ipairs({ "<M-c>", "ç" }) do
    map(lhs, toggle("case"), { "i" })
  end
  for _, lhs in ipairs({ "<M-w>", "∑" }) do
    map(lhs, toggle("word"), { "i" })
  end
  for _, lhs in ipairs({ "<M-x>", "≈" }) do
    map(lhs, toggle("regex"), { "i" })
  end
  for _, lhs in ipairs({ "<M-p>", "π" }) do
    map(lhs, function()
      if state.replace then
        M.replace_one()
      end
    end, { "i" })
  end
  for _, lhs in ipairs({ "<M-a>", "å" }) do
    map(lhs, function()
      if state.replace then
        M.replace_all()
      end
    end, { "i" })
  end
  map("<D-f>", function()
    show_replace(false)
  end)
  map("<D-r>", function()
    -- Cmd+R pressed twice: LSP rename, as Cmd+R Cmd+R did before the bar
    if state.by_r and (vim.uv.now() - state.opened_at) < 800 then
      M.close()
      vim.lsp.buf.rename()
      return
    end
    show_replace(true)
  end)
  -- one line per field: Backspace at the start and Delete at the end don't join them
  vim.keymap.set("i", "<BS>", function()
    return api.nvim_win_get_cursor(0)[2] == 0 and "" or "<BS>"
  end, { buffer = buf, expr = true, nowait = true })
  vim.keymap.set("i", "<Del>", function()
    local c = api.nvim_win_get_cursor(0)
    return c[2] >= #api.nvim_get_current_line() and "" or "<Del>"
  end, { buffer = buf, expr = true, nowait = true })
  map("<LeftMouse>", click)
  map("<2-LeftMouse>", click)
end

-- Text pasted with line breaks stays on its field.
local function keep_lines()
  local lines = api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local want = state.replace and 2 or 1
  if #lines == want then
    return
  end
  local new
  if want == 1 then
    new = { table.concat(lines, " ") }
  elseif #lines > 2 then
    new = { lines[1], table.concat(lines, " ", 2) }
  else
    new = { lines[1] or "", "" }
  end
  api.nvim_buf_set_lines(state.buf, 0, -1, false, new)
  local r = math.min(api.nvim_win_get_cursor(state.win)[1], want)
  api.nvim_win_set_cursor(state.win, { r, #new[r] })
end

-- Select the text of the find field (Select mode), so typing replaces it like in a text field.
local function select_find()
  vim.schedule(function()
    if state and alive() and api.nvim_get_current_win() == state.win and api.nvim_buf_get_lines(state.buf, 0, 1, false)[1] ~= "" then
      api.nvim_feedkeys(vim.keycode("<Esc>$v0<C-g>"), "n", false)
    end
  end)
end

--- Open the bar on the current window. `o.replace` shows the replace field, `o.text` fills the
--- find field (else the last search).
function M.open(o)
  o = o or {}
  if state then
    local current = api.nvim_get_current_win()
    if alive() and (current == state.win or current == state.target) then
      -- already open on this window: back into it (with the new selection, if any)
      api.nvim_set_current_win(state.win)
      if o.text then
        api.nvim_buf_set_lines(state.buf, 0, 1, false, { o.text })
      end
      state.origin = api.nvim_win_get_cursor(state.target)
      show_replace(o.replace or false)
      if o.text then
        M.update(true)
      end
      vim.cmd("startinsert!")
      if not o.replace then
        select_find()
      end
      return
    end
    M.close()
  end
  local target = api.nvim_get_current_win()
  local find = o.text or last.find
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "findbar"
  vim.b[buf].completion = false -- blink.cmp
  vim.b[buf].minipairs_disable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, { find })
  local win = api.nvim_open_win(
    buf,
    true,
    vim.tbl_extend(
      "force",
      geometry(target, 1),
      { style = "minimal", border = "rounded", zindex = 60 }
    )
  )
  vim.wo[win].signcolumn = "yes:1"
  vim.wo[win].wrap = false
  vim.wo[win].winhighlight = "NormalFloat:NormalFloat,FloatBorder:FloatBorder"
  state = {
    win = win,
    buf = buf,
    target = target,
    tbuf = api.nvim_win_get_buf(target),
    origin = api.nvim_win_get_cursor(target),
    replace = false,
    buttons = {},
    opened_at = vim.uv.now(),
    by_r = o.replace or false,
  }
  keymaps(buf)
  local group = api.nvim_create_augroup("FindBar", { clear = true })
  api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    group = group,
    buffer = buf,
    callback = function()
      if not alive() then
        return
      end
      keep_lines()
      local r = api.nvim_win_get_cursor(state.win)[1]
      if r == 1 then
        M.update(true)
      else
        last.replace = select(2, fields())
      end
    end,
  })
  -- The bar stays open while you work in the file: typing there leaves insert mode behind, coming
  -- back (a click, / or Cmd+F) types into it again. Edits and moves in the file update the count.
  api.nvim_create_autocmd("WinLeave", {
    group = group,
    buffer = buf,
    callback = function()
      vim.cmd("stopinsert")
    end,
  })
  api.nvim_create_autocmd("WinEnter", {
    group = group,
    buffer = buf,
    callback = function()
      vim.cmd("startinsert!")
    end,
  })
  api.nvim_create_autocmd({ "CursorMoved", "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = state.tbuf,
    callback = function()
      if alive() then
        local pat = pattern((fields()))
        if pat and valid(pat) then
          show_current(pat, false)
        end
        draw()
      end
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(target),
    callback = function()
      vim.schedule(M.close)
    end,
  })
  -- a click on the bar's buttons works from the file too (the bar's own mapping only fires in it)
  for _, mode in ipairs({ "n", "x", "i" }) do
    vim.keymap.set(mode, "<LeftMouse>", function()
      if alive() then
        click()
      else
        api.nvim_feedkeys(vim.keycode("<LeftMouse>"), "n", false)
      end
    end, { desc = "Click (find bar buttons)" })
  end
  api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      if alive() then
        resize()
        draw()
      end
    end,
  })
  if o.replace then
    show_replace(true)
    if find == "" then
      api.nvim_win_set_cursor(win, { 1, 0 })
    end
  else
    api.nvim_win_set_cursor(win, { 1, #find })
    M.update(true)
  end
  vim.cmd("startinsert!")
  if not o.replace then
    select_find()
  end
end

-- The visual selection (first line), leaving visual mode.
local function selection()
  local region = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
  vim.cmd("normal! \27")
  return (region[1] or "")
end

function M.setup()
  local function find()
    M.open()
  end
  local function replace()
    M.open({ replace = true })
  end
  vim.keymap.set("n", "/", find, { desc = "Find" })
  vim.keymap.set("n", "<D-f>", find, { desc = "Find" })
  vim.keymap.set("n", "<D-r>", replace, { desc = "Replace (twice: rename symbol)" })
  vim.keymap.set("x", "/", function()
    M.open({ text = selection() })
  end, { desc = "Find selection" })
  vim.keymap.set("x", "<D-f>", function()
    M.open({ text = selection() })
  end, { desc = "Find selection" })
  vim.keymap.set("x", "<D-r>", function()
    M.open({ text = selection(), replace = true })
  end, { desc = "Replace selection" })
end

return M
