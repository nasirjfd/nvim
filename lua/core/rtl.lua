-- Right-to-left text (Persian, Arabic, Hebrew, ...) in a terminal that draws every character left to
-- right in logical order (Ghostty has no bidi). GNU FriBidi (`brew install fribidi`, loaded through
-- LuaJIT FFI) computes the visual order and joins the letters; the result is drawn over the line as an
-- overlay.
--
-- What it never does, so English editing stays exactly as it is:
--   * change the buffer, an option or the cursor (no conceallevel, no guicursor, no keymaps);
--   * draw on the cursor line of a window (the real text is edited there), on a line without RTL
--     letters, in a window with 'rightleft', or in a special buffer that did not opt in (pickers,
--     prompts, input boxes, terminals; see `allowed`).
-- Decorations are ephemeral (made at redraw time), nothing is stored in the buffer.
-- :Rtl toggles it. Without FriBidi it does nothing and says once how to install it.
local M = {}

local ns = vim.api.nvim_create_namespace("rtl_text")
local enabled = true

local ffi_ok, ffi = pcall(require, "ffi")
local lib -- the FriBidi library, nil when not found

local LIBRARY_PATHS = {
  "fribidi",
  "/opt/homebrew/opt/fribidi/lib/libfribidi.0.dylib",
  "/usr/local/opt/fribidi/lib/libfribidi.0.dylib",
  "libfribidi.so.0",
}

local PAR_LTR = 0x110 -- FRIBIDI_PAR_LTR: lines keep their left-to-right structure (code, indentation)

local function load()
  if lib ~= nil or not ffi_ok then
    return lib
  end
  pcall(
    ffi.cdef,
    [[
    typedef uint32_t FriBidiChar;
    typedef int FriBidiStrIndex;
    typedef uint32_t FriBidiParType;
    typedef signed char FriBidiLevel;
    FriBidiLevel fribidi_log2vis(const FriBidiChar *str, const FriBidiStrIndex len,
      FriBidiParType *pbase_dir, FriBidiChar *visual_str, FriBidiStrIndex *positions_L_to_V,
      FriBidiStrIndex *positions_V_to_L, FriBidiLevel *embedding_levels);
  ]]
  )
  for _, path in ipairs(LIBRARY_PATHS) do
    local ok, l = pcall(ffi.load, path)
    if ok then
      lib = l
      return lib
    end
  end
  lib = false
  return lib
end

function M.available()
  return load() and true or false
end

-- RTL scripts in UTF-8: U+0590-077F (Hebrew, Arabic, Syriac, Arabic Supplement, Thaana lead bytes
-- D6-DD), U+08A0-08FF (Arabic Extended-A), U+FB1D-FEFF (Hebrew/Arabic presentation forms).
function M.has_rtl(line)
  return line:find("[\214-\221]") ~= nil
    or line:find("\224[\162\163]") ~= nil
    or line:find("\239[\172-\187]") ~= nil
end

local function decode(s)
  local cps, offs, i, n = {}, {}, 1, #s
  while i <= n do
    local c = s:byte(i)
    local cp, len
    if c < 0x80 then
      cp, len = c, 1
    elseif c >= 0xF0 then
      cp, len = c % 0x08, 4
    elseif c >= 0xE0 then
      cp, len = c % 0x10, 3
    elseif c >= 0xC0 then
      cp, len = c % 0x20, 2
    else
      cp, len = 0xFFFD, 1 -- stray continuation byte
    end
    for k = 1, len - 1 do
      local b = s:byte(i + k)
      if not b or b < 0x80 or b >= 0xC0 then
        cp, len = 0xFFFD, k
        break
      end
      cp = cp * 64 + (b % 64)
    end
    cps[#cps + 1] = cp
    offs[#offs + 1] = i
    i = i + len
  end
  return cps, offs
end

local function encode(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
  elseif cp < 0x10000 then
    return string.char(
      0xE0 + math.floor(cp / 4096),
      0x80 + math.floor(cp / 64) % 64,
      0x80 + cp % 64
    )
  end
  return string.char(
    0xF0 + math.floor(cp / 262144),
    0x80 + math.floor(cp / 4096) % 64,
    0x80 + math.floor(cp / 64) % 64,
    0x80 + cp % 64
  )
end

-- Invisible format characters (ZWNJ, ZWJ, bidi marks, BOM / FriBidi's ligature filler). Neovim shows
-- them as <200c> (several cells); the overlay draws them as nothing.
local function invisible(cp)
  return (cp >= 0x200B and cp <= 0x200F)
    or (cp >= 0x202A and cp <= 0x202E)
    or (cp >= 0x2060 and cp <= 0x2069)
    or cp == 0xFEFF
end

local cache, cache_size = {}, 0

---The overlay of a line: where it starts (byte column) and the text drawn there, or nil when the line
---looks the same in visual order.
---@param line string
---@param tabstop integer
---@return { col: integer, text: string }|nil
function M.render(line, tabstop)
  if not M.has_rtl(line) or not load() then
    return nil
  end
  local key = tabstop .. "\0" .. line
  local hit = cache[key]
  if hit ~= nil then
    return hit or nil
  end
  local cps, offs = decode(line)
  local n = #cps
  local input = ffi.new("FriBidiChar[?]", n)
  for k = 1, n do
    input[k - 1] = cps[k]
  end
  local output = ffi.new("FriBidiChar[?]", n + 1)
  local base = ffi.new("FriBidiParType[1]", PAR_LTR)
  local result = false
  if lib.fribidi_log2vis(input, n, base, output, nil, nil, nil) ~= 0 then
    local first, last
    for k = 1, n do
      local v = tonumber(output[k - 1])
      if v ~= cps[k] or invisible(cps[k]) then
        first = first or k
        last = k
      end
    end
    if first then
      local start_byte = offs[first]
      local end_byte = (offs[last + 1] or (#line + 1)) - 1
      local col0 = vim.fn.strdisplaywidth(line:sub(1, start_byte - 1))
      local width = vim.fn.strdisplaywidth(line:sub(1, end_byte)) - col0
      local parts, col = {}, col0
      local function put(v)
        if v == 9 then
          local spaces = tabstop - (col % tabstop)
          parts[#parts + 1] = string.rep(" ", spaces)
          col = col + spaces
        elseif not invisible(v) then
          local ch = encode(v)
          parts[#parts + 1] = ch
          col = col + vim.fn.strdisplaywidth(ch)
        end
      end
      for k = first, last do
        put(tonumber(output[k - 1]))
      end
      -- Invisible characters (ZWNJ) take cells in the real line but none in the overlay. The text after
      -- them moves left to close the gap, up to the first run of spaces that can absorb it (a table
      -- cell's padding: the next column stays where it is), or to the end of the line.
      local missing = width - (col - col0)
      if missing > 0 then
        local spaces = 0
        for k = last + 1, n do
          if cps[k] == 32 then
            spaces = spaces + 1
            if spaces == missing then
              missing = 0
              break
            end
          else
            for _ = 1, spaces do
              put(32)
            end
            spaces = 0
            put(cps[k])
          end
        end
        -- Absorbed: the overlay ends before those spaces (the real ones show there). Otherwise it ran to
        -- the end of the line: blank the cells the moved text left.
        if missing > 0 then
          parts[#parts + 1] = string.rep(" ", spaces + missing)
        end
      end
      result = { col = start_byte - 1, text = table.concat(parts) }
    end
  end
  if cache_size > 4000 then
    cache, cache_size = {}, 0
  end
  cache[key] = result
  cache_size = cache_size + 1
  return result or nil
end

local warned = false
local function warn_missing()
  if warned then
    return
  end
  warned = true
  vim.schedule(function()
    vim.notify(
      "Right-to-left text needs GNU FriBidi: brew install fribidi (then restart Neovim)",
      vim.log.levels.WARN,
      { title = "RTL" }
    )
  end)
end

local skip_row = {} -- window -> its cursor row (drawn raw), set in on_win

-- Ordinary files and write-through buffers (the row edit form). Other special buffers only when they
-- opt in with `vim.b.rtl_text = true` (dbee's result pane): pickers, prompts, input boxes and
-- terminals are never drawn on.
local function allowed(buf)
  local bt = vim.bo[buf].buftype
  return bt == "" or bt == "acwrite" or vim.b[buf].rtl_text == true
end

function M.setup()
  vim.api.nvim_set_decoration_provider(ns, {
    on_win = function(_, win, buf)
      if not enabled or not allowed(buf) or vim.wo[win].rightleft then
        return false
      end
      skip_row[win] = vim.api.nvim_win_get_cursor(win)[1] - 1
    end,
    on_line = function(_, win, buf, row)
      if row == skip_row[win] then
        return
      end
      local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
      if not line or not M.has_rtl(line) then
        return
      end
      if not load() then
        return warn_missing()
      end
      local r = M.render(line, vim.bo[buf].tabstop)
      if r then
        vim.api.nvim_buf_set_extmark(buf, ns, row, r.col, {
          virt_text = { { r.text, "" } },
          virt_text_pos = "overlay",
          hl_mode = "combine",
          ephemeral = true,
        })
      end
    end,
  })

  -- The cursor line is drawn raw: when the cursor leaves or enters a line with RTL text, redraw both
  -- lines. Lines without RTL text are never redrawn by this.
  local last_row = {}
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufWinEnter" }, {
    group = vim.api.nvim_create_augroup("rtl_text", { clear = true }),
    callback = function(ev)
      if not enabled or not allowed(ev.buf) then
        return
      end
      local win = vim.api.nvim_get_current_win()
      local row = vim.api.nvim_win_get_cursor(win)[1] - 1
      local prev = last_row[win]
      last_row[win] = row
      if prev == row then
        return
      end
      for _, r in ipairs({ prev, row }) do
        local line = r and vim.api.nvim_buf_get_lines(ev.buf, r, r + 1, false)[1]
        if line and M.has_rtl(line) then
          pcall(vim.api.nvim__redraw, { win = win, range = { r, r + 1 }, valid = false })
        end
      end
    end,
  })

  vim.api.nvim_create_user_command("Rtl", function()
    enabled = not enabled
    vim.cmd("redraw!")
    vim.notify(
      "Right-to-left text " .. (enabled and "on" or "off"),
      vim.log.levels.INFO,
      { title = "RTL" }
    )
  end, { desc = "Toggle drawing right-to-left text in visual order" })
end

return M
