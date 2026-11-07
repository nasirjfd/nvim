-- Persian / Arabic script in a terminal that cannot shape or reorder it.
-- The terminal draws every letter in its isolated form, left to right. This module draws, on lines
-- other than the insert-mode cursor line, the shaped letters (initial/medial/final forms, lam-alef ligatures) in
-- visual right-to-left order on top of the text. The buffer is never changed: the cursor line, yanks,
-- search and files all keep the logical text. Toggle with :PersianShaping.
local M = {}

local ns = vim.api.nvim_create_namespace("persian_shaping")
local enabled = true

-- base letter -> { isolated, final, initial, medial } (right-joining letters have two forms)
local forms = {}
local function add(base, ...)
  forms[base] = { ... }
end
local dual = {
  [0x0626] = 0xFE89, [0x0628] = 0xFE8F, [0x062A] = 0xFE95, [0x062B] = 0xFE99, [0x062C] = 0xFE9D,
  [0x062D] = 0xFEA1, [0x062E] = 0xFEA5, [0x0633] = 0xFEB1, [0x0634] = 0xFEB5, [0x0635] = 0xFEB9,
  [0x0636] = 0xFEBD, [0x0637] = 0xFEC1, [0x0638] = 0xFEC5, [0x0639] = 0xFEC9, [0x063A] = 0xFECD,
  [0x0641] = 0xFED1, [0x0642] = 0xFED5, [0x0643] = 0xFED9, [0x0644] = 0xFEDD, [0x0645] = 0xFEE1,
  [0x0646] = 0xFEE5, [0x0647] = 0xFEE9, [0x064A] = 0xFEF1, [0x067E] = 0xFB56, [0x0686] = 0xFB7A,
  [0x06A9] = 0xFB8E, [0x06AF] = 0xFB92, [0x06CC] = 0xFBFC,
}
for base, iso in pairs(dual) do
  add(base, iso, iso + 1, iso + 2, iso + 3)
end
local right = {
  [0x0622] = 0xFE81, [0x0623] = 0xFE83, [0x0624] = 0xFE85, [0x0625] = 0xFE87, [0x0627] = 0xFE8D,
  [0x0629] = 0xFE93, [0x062F] = 0xFEA9, [0x0630] = 0xFEAB, [0x0631] = 0xFEAD, [0x0632] = 0xFEAF,
  [0x0648] = 0xFEED, [0x0649] = 0xFEEF, [0x0698] = 0xFB8A,
}
for base, iso in pairs(right) do
  add(base, iso, iso + 1)
end
add(0x0621, 0xFE80) -- hamza: never joins
-- lam + alef variants: { isolated, final }
local lam_alef = {
  [0x0622] = { 0xFEF5, 0xFEF6 }, [0x0623] = { 0xFEF7, 0xFEF8 },
  [0x0625] = { 0xFEF9, 0xFEFA }, [0x0627] = { 0xFEFB, 0xFEFC },
}

local function can_join_next(cp) -- joins to the letter that follows it
  local f = forms[cp]
  return f ~= nil and #f == 4
end
local function can_join_prev(cp) -- accepts a join from the letter before it
  local f = forms[cp]
  return f ~= nil and #f >= 2
end

local function is_mark(cp)
  return (cp >= 0x064B and cp <= 0x065F) or cp == 0x0670 or (cp >= 0x06D6 and cp <= 0x06ED)
end
local function is_rtl(cp)
  return (cp >= 0x0600 and cp <= 0x06FF and not (cp >= 0x06F0 and cp <= 0x06F9))
    or (cp >= 0x0750 and cp <= 0x077F)
    or cp == 0x200C
    or cp == 0x200D
    or (cp >= 0xFB50 and cp <= 0xFDFF)
    or (cp >= 0xFE70 and cp <= 0xFEFF)
end
local function is_digit(cp)
  return (cp >= 0x30 and cp <= 0x39) or (cp >= 0x06F0 and cp <= 0x06F9) or (cp >= 0x0660 and cp <= 0x0669)
end
local function is_alnum(cp)
  return is_digit(cp) or (cp >= 0x41 and cp <= 0x5A) or (cp >= 0x61 and cp <= 0x7A)
end
-- mirrored in a right-to-left run
local mirror = { ["("] = ")", [")"] = "(", ["["] = "]", ["]"] = "[", ["{"] = "}", ["}"] = "{", ["<"] = ">", [">"] = "<", ["«"] = "»", ["»"] = "«" }

--- Shape and reorder one logical run. `chars` is a list of { cp=, s= } in logical order.
--- Returns the visual string and the byte offsets of every ZWNJ (to conceal).
local function shape(chars)
  -- clusters: base letter plus its marks
  local cl = {}
  for _, c in ipairs(chars) do
    if is_mark(c.cp) and #cl > 0 and not cl[#cl].neutral then
      cl[#cl].marks = cl[#cl].marks .. c.s
    else
      cl[#cl + 1] = { cp = c.cp, s = c.s, marks = "" }
    end
  end
  -- drop ZWNJ/ZWJ after using them as join breakers
  local out = {}
  local i, n = 1, #cl
  local prev_joins = false -- previous letter wants to join the next one
  while i <= n do
    local c = cl[i]
    local cp = c.cp
    if cp == 0x200C then
      prev_joins = false
      i = i + 1
    elseif cp == 0x200D then
      prev_joins = true
      i = i + 1
    elseif forms[cp] then
      -- lam + alef ligature
      local nxt = cl[i + 1]
      -- (the ligature glyph is drawn two cells wide by some terminals: lam and alef stay separate)
      if false and cp == 0x0644 and nxt and lam_alef[nxt.cp] then
        local f = lam_alef[nxt.cp]
        out[#out + 1] = vim.fn.nr2char(prev_joins and f[2] or f[1]) .. c.marks .. nxt.marks
        prev_joins = false
        i = i + 2
      else
        local f = forms[cp]
        local nx = cl[i + 1]
        local joins_next = can_join_next(cp) and nx ~= nil and forms[nx.cp] ~= nil and can_join_prev(nx.cp)
        local idx
        if prev_joins and joins_next then
          idx = 4 -- medial
        elseif prev_joins then
          idx = 2 -- final
        elseif joins_next then
          idx = 3 -- initial
        else
          idx = 1
        end
        out[#out + 1] = vim.fn.nr2char(f[idx] or f[1]) .. c.marks
        prev_joins = joins_next
        i = i + 1
      end
    else
      out[#out + 1] = c.s .. c.marks
      prev_joins = false
      i = i + 1
    end
  end
  -- reorder: runs of digits/latin stay left to right, everything else is reversed
  local vis, k = {}, #out
  local seg = {}
  local function flush()
    for j = 1, #seg do
      vis[#vis + 1] = seg[j]
    end
    seg = {}
  end
  -- walk from the logical end so the result reads right to left
  local items = {}
  for _, piece in ipairs(out) do
    items[#items + 1] = piece
  end
  local result = {}
  local idx = #items
  while idx >= 1 do
    local p = items[idx]
    local cp = vim.fn.char2nr(p)
    if is_alnum(cp) then
      local j = idx
      while j - 1 >= 1 and is_alnum(vim.fn.char2nr(items[j - 1])) do
        j = j - 1
      end
      for x = j, idx do
        result[#result + 1] = items[x]
      end
      idx = j - 1
    else
      result[#result + 1] = mirror[p] or p
      idx = idx - 1
    end
  end
  flush()
  return table.concat(result), k
end

local function decode(str)
  local out = {}
  local starts = vim.str_utf_pos(str)
  for i, a in ipairs(starts) do
    local b = (starts[i + 1] or #str + 1) - 1
    local ch = str:sub(a, b)
    out[#out + 1] = { cp = vim.fn.char2nr(ch), s = ch, b = a - 1 }
  end
  return out
end

--- Split a line into the byte ranges that need shaping.
local cache = {}
local function runs_of(line)
  local hit = cache[line]
  if hit then
    return hit
  end
  local list = {}
  local chars = {}
  for _, c in ipairs(decode(line)) do
    chars[#chars + 1] = c
  end
  local n = #chars
  local i = 1
  while i <= n do
    if is_rtl(chars[i].cp) and chars[i].cp ~= 0x200C and chars[i].cp ~= 0x200D then
      local first, last = i, i
      local j = i
      while j <= n do
        local cp = chars[j].cp
        if is_rtl(cp) or is_mark(cp) then
          last = j
          j = j + 1
        elseif cp == 0x20 or is_alnum(cp) or cp == 0x2E or cp == 0x2C or cp == 0x21 or cp == 0x3A
          or cp == 0x28 or cp == 0x29 or cp == 0x2D or cp == 0x3F then
          -- neutrals and numbers stay in the run only when more Persian follows
          j = j + 1
        else
          break
        end
        if j <= n and not (is_rtl(chars[j].cp) or is_mark(chars[j].cp)) then
          -- look ahead: is there Persian before the run really ends?
          local k = j
          while k <= n and (chars[k].cp == 0x20 or is_alnum(chars[k].cp) or chars[k].cp == 0x2E
            or chars[k].cp == 0x2C or chars[k].cp == 0x21 or chars[k].cp == 0x3A or chars[k].cp == 0x28
            or chars[k].cp == 0x29 or chars[k].cp == 0x2D or chars[k].cp == 0x3F) do
            k = k + 1
          end
          if not (k <= n and is_rtl(chars[k].cp)) then
            -- trailing digits stay attached (one space allowed): "تست 12"
            local m = j
            if chars[m] and chars[m].cp == 0x20 then
              m = m + 1
            end
            if chars[m] and is_digit(chars[m].cp) then
              while m <= n and is_digit(chars[m].cp) do
                last = m
                m = m + 1
              end
            end
            break
          end
        end
      end
      local run = {}
      local zwnj = {}
      for x = first, last do
        run[#run + 1] = chars[x]
        if chars[x].cp == 0x200C then
          zwnj[#zwnj + 1] = { chars[x].b, chars[x].b + #chars[x].s }
        end
      end
      local visual = shape(run)
      -- cells the original occupies once ZWNJ is concealed
      local width = 0
      for x = first, last do
        if chars[x].cp ~= 0x200C then
          width = width + vim.fn.strdisplaywidth(chars[x].s)
        end
      end
      local vw = vim.fn.strdisplaywidth(visual)
      if vw < width then
        visual = string.rep(" ", width - vw) .. visual
      end
      list[#list + 1] = {
        col = chars[first].b,
        end_col = chars[last].b + #chars[last].s,
        text = visual,
        zwnj = zwnj,
      }
      i = last + 1
    else
      i = i + 1
    end
  end
  if vim.tbl_count(cache) > 2000 then
    cache = {}
  end
  cache[line] = list
  return list
end

function M.has_persian(line)
  return line:find("[\216-\219\239]") ~= nil
end

function M.setup()
  -- Neovim's own Arabic shaping would re-join the glyphs drawn here and eat cells
  vim.o.arabicshape = false
  vim.api.nvim_set_decoration_provider(ns, {
    on_win = function(_, _, bufnr)
      return enabled and vim.bo[bufnr].buftype ~= "terminal"
    end,
    on_line = function(_, winid, bufnr, row)
      local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
      if not line or not M.has_persian(line) then
        return
      end
      -- while typing, the cursor line stays raw: that is the text you edit
      if vim.api.nvim_get_current_win() == winid and vim.fn.mode():sub(1, 1) == "i" and vim.api.nvim_win_get_cursor(winid)[1] == row + 1 then
        return
      end
      for _, run in ipairs(runs_of(line)) do
        for _, z in ipairs(run.zwnj) do
          vim.api.nvim_buf_set_extmark(bufnr, ns, row, z[1], { end_col = z[2], conceal = "", ephemeral = true })
        end
        vim.api.nvim_buf_set_extmark(bufnr, ns, row, run.col, {
          virt_text = { { run.text, "" } },
          virt_text_pos = "overlay",
          hl_mode = "combine",
          ephemeral = true,
        })
      end
    end,
  })

  -- concealing ZWNJ needs conceallevel in windows that show Persian text
  vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "InsertLeave" }, {
    callback = function(args)
      if not enabled or vim.bo[args.buf].buftype ~= "" then
        return
      end
      local win = vim.api.nvim_get_current_win()
      if vim.api.nvim_win_get_buf(win) ~= args.buf or vim.wo[win].conceallevel >= 1 then
        return
      end
      for _, l in ipairs(vim.api.nvim_buf_get_lines(args.buf, 0, math.min(vim.api.nvim_buf_line_count(args.buf), 5000), false)) do
        if M.has_persian(l) then
          vim.wo[win].conceallevel = 2
          return
        end
      end
    end,
  })

  -- the cursor line is drawn raw in insert mode: redraw it when the mode or line changes
  local last = {}
  vim.api.nvim_create_autocmd({ "ModeChanged", "CursorMovedI" }, {
    callback = function()
      if not enabled then
        return
      end
      local win = vim.api.nvim_get_current_win()
      local row = vim.api.nvim_win_get_cursor(win)[1] - 1
      local prev = last[win]
      last[win] = row
      pcall(vim.api.nvim__redraw, { win = win, range = { math.min(prev or row, row), math.max(prev or row, row) + 1 } })
    end,
  })

  vim.api.nvim_create_user_command("PersianShaping", function()
    enabled = not enabled
    vim.cmd("redraw!")
    vim.notify("Persian shaping " .. (enabled and "on" or "off"))
  end, {})
end

M._runs = function(l) return runs_of(l) end
M._shape = function(s)
  return (shape(decode(s)))
end

return M
