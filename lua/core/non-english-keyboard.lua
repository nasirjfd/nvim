-- Non-English keyboard-position translation; ordinary editor text is unchanged.
local M = {}
-- Every alias's description ends with it. Shortcut lists (which-key, the keymaps picker) leave the aliases out:
-- they only repeat an English shortcut on the Persian layout.
M.SUFFIX = " (non-English keyboard)"

--- Is this mapping (or its description) one of the Persian-layout aliases?
function M.is_alias(mapping)
  local desc = type(mapping) == "table" and mapping.desc or mapping
  return type(desc) == "string" and desc:sub(-#M.SUFFIX) == M.SUFFIX
end
local api = vim.api
local letters = {
  ["ض"] = "q",
  ["ص"] = "w",
  ["ث"] = "e",
  ["ق"] = "r",
  ["ف"] = "t",
  ["غ"] = "y",
  ["ع"] = "u",
  ["ه"] = "i",
  ["خ"] = "o",
  ["ح"] = "p",
  ["ج"] = "[",
  ["چ"] = "]",
  ["ش"] = "a",
  ["س"] = "s",
  ["ی"] = "d",
  ["ي"] = "d",
  ["ب"] = "f",
  ["ل"] = "g",
  ["ا"] = "h",
  ["ت"] = "j",
  ["ن"] = "k",
  ["م"] = "l",
  ["ک"] = ";",
  ["ك"] = ";",
  ["گ"] = "'",
  ["ظ"] = "z",
  ["ط"] = "x",
  ["ز"] = "c",
  ["ر"] = "v",
  ["ذ"] = "b",
  ["د"] = "n",
  ["پ"] = "m",
  ["و"] = ",",
  ["۰"] = "0",
  ["۱"] = "1",
  ["۲"] = "2",
  ["۳"] = "3",
  ["۴"] = "4",
  ["۵"] = "5",
  ["۶"] = "6",
  ["۷"] = "7",
  ["۸"] = "8",
  ["۹"] = "9",
}
local physical = {}
for character, english in pairs(letters) do
  if character ~= "ي" and character ~= "ك" then
    physical[english] = character
  end
end
local modes = { "n", "x", "o", "i", "s", "c", "t" }
local alert = { generation = 0 }

local function dismiss_alert()
  if not alert.pending and not alert.win then
    return
  end
  alert.generation = alert.generation + 1
  local generation = alert.generation
  alert.pending = nil
  if alert.timer then
    alert.timer:stop()
  end
  -- Key listeners run under textlock; closing the float must be scheduled.
  vim.schedule(function()
    if generation == alert.generation and alert.win and api.nvim_win_is_valid(alert.win) then
      api.nvim_win_close(alert.win, true)
      alert.win = nil
    end
  end)
end

local function show_alert()
  alert.generation = alert.generation + 1
  local generation = alert.generation
  alert.timer = alert.timer or assert(vim.uv.new_timer())
  alert.timer:stop()
  alert.timer:start(
    1500,
    0,
    vim.schedule_wrap(function()
      if generation == alert.generation and alert.win and api.nvim_win_is_valid(alert.win) then
        api.nvim_win_close(alert.win, true)
        alert.win = nil
      end
    end)
  )
  -- Key listeners and expression mappings run under textlock. Coalesce bursts
  -- into one scheduled, non-focusable window, not a notification per key.
  if alert.pending then
    return
  end
  local pending = {}
  alert.pending = pending
  vim.schedule(function()
    if alert.pending ~= pending then
      return
    end
    alert.pending = false
    if alert.win and api.nvim_win_is_valid(alert.win) then
      return
    end
    local text = "   ⌨   Switch to English keyboard layout   "
    local pad = string.rep(" ", vim.fn.strdisplaywidth(text))
    local width = math.min(vim.fn.strdisplaywidth(text) + 8, math.max(1, vim.o.columns - 4))
    local function centered(line)
      local gap = math.max(0, width - vim.fn.strdisplaywidth(line))
      return string.rep(" ", math.floor(gap / 2)) .. line
    end
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "non_english_keyboard_alert"
    api.nvim_buf_set_lines(buf, 0, -1, false, { pad, pad, centered(text), pad, pad })
    alert.win = api.nvim_open_win(buf, false, {
      relative = "editor",
      row = 0,
      col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
      width = width,
      height = 5,
      style = "minimal",
      border = "double",
      focusable = false,
      mouse = false,
      zindex = 250,
      noautocmd = true,
    })
    vim.wo[alert.win].winhighlight = "Normal:ErrorMsg,FloatBorder:ErrorMsg"
  end)
end

function M.english(text)
  return (text:gsub("[\194-\244][\128-\191]+", letters))
end

local function search(buf)
  local ft = vim.bo[buf].filetype
  return ft == "snacks_picker_input" or (ft == "findbar" and api.nvim_win_get_cursor(0)[1] == 1)
end

-- Names are English even when the keyboard is not. Content searches keep the
-- optional toggle so searching actual non-English text still works.
local name_sources = {
  files = true,
  recent = true,
  buffers = true,
  smart = true,
  lsp_symbols = true,
  lsp_workspace_symbols = true,
}

local function name_picker(buf)
  if vim.bo[buf].filetype ~= "snacks_picker_input" then
    return
  end
  for _, picker in ipairs(Snacks.picker.get()) do
    if picker.input and picker.input.win.buf == buf and name_sources[picker.opts.source] then
      return picker
    end
  end
end

local function normalize_names(buf)
  local picker = name_picker(buf)
  if not picker then
    return
  end
  local text = api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
  local translated = M.english(text)
  if translated == text then
    return
  end
  local win = picker.input.win.win
  local cursor = api.nvim_win_get_cursor(win)
  picker.input:set(picker.opts.live and nil or translated, picker.opts.live and translated or nil)
  api.nvim_win_set_cursor(win, { 1, #M.english(text:sub(1, cursor[2])) })
  picker:find({ refresh = false })
end

function M.toggle(value)
  local enabled = value
  if enabled == nil then
    enabled = not vim.g.non_english_search
  end
  vim.g.non_english_search = enabled
  local buf = api.nvim_get_current_buf()
  if enabled and search(buf) then
    local cursor = api.nvim_win_get_cursor(0)
    local text = api.nvim_get_current_line()
    local translated = M.english(text)
    if translated ~= text then
      api.nvim_buf_set_lines(buf, cursor[1] - 1, cursor[1], false, { translated })
      api.nvim_win_set_cursor(0, { cursor[1], #M.english(text:sub(1, cursor[2])) })
    end
  end
  vim.notify("English search from non-English keyboard: " .. (enabled and "on" or "off"))
end

-- Alias modified shortcuts to the existing English mapping, including maps
-- added later by a plugin. Never translate ordinary insert-mode text.
function M.shortcuts(buf)
  for _, mode in ipairs(modes) do
    local maps = buf and api.nvim_buf_get_keymap(buf, mode) or api.nvim_get_keymap(mode)
    local existing = {}
    for _, mapping in ipairs(maps) do
      existing[mapping.lhs] = true
    end
    for _, mapping in ipairs(maps) do
      local function modified(key)
        local modifiers, letter = key:match("^(.-%-)(.)$")
        local replacement = letter and physical[letter:lower()]
        if not replacement then
          return "<" .. key .. ">"
        end
        if letter:match("%u") and not modifiers:find("S%-") and not modifiers:find("C%-") then
          modifiers = modifiers .. "S-"
        end
        return "<" .. modifiers .. replacement .. ">"
      end
      local function literal(text)
        if mode ~= "n" and mode ~= "x" and mode ~= "o" then
          return text
        end
        return (text:gsub("[a-z]", physical))
      end
      local parts, offset = {}, 1
      for first, key, last in mapping.lhs:gmatch("()<([^>]+)>()") do
        parts[#parts + 1] = literal(mapping.lhs:sub(offset, first - 1))
        parts[#parts + 1] = modified(key)
        offset = last
      end
      parts[#parts + 1] = literal(mapping.lhs:sub(offset))
      local alias = table.concat(parts)
      if
        alias ~= mapping.lhs
        and not existing[alias]
        and not mapping.lhs:find("<Plug>", 1, true)
        and not mapping.lhs:find("<SNR>", 1, true)
        and #vim.keycode(alias) <= 50
      then
        vim.keymap.set(mode, alias, mapping.lhs, {
          buffer = buf,
          remap = true,
          silent = mapping.silent == 1,
          nowait = mapping.nowait == 1,
          desc = (mapping.desc or "Shortcut") .. M.SUFFIX,
        })
      end
    end
  end
end

function M.attach(buf)
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  if vim.bo[buf].filetype == "snacks_picker_input" or vim.bo[buf].filetype == "findbar" then
    if not vim.b[buf].non_english_search_keys then
      vim.b[buf].non_english_search_keys = true
      for character, english in pairs(letters) do
        vim.keymap.set({ "i", "s" }, character, function()
          if name_picker(buf) or vim.g.non_english_search and search(buf) then
            return english
          end
          return character
        end, {
          buffer = buf,
          expr = true,
          desc = "Optional English text search from non-English keyboard",
        })
      end
      vim.keymap.set({ "i", "n", "s" }, "<C-S-l>", function()
        M.toggle()
      end, { buffer = buf, desc = "Toggle non-English keyboard English text search" })
      -- Pasting and prefilled queries bypass insert-mode key mappings.
      api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = buf,
        callback = function()
          normalize_names(buf)
        end,
      })
    end
    normalize_names(buf)
  end
  M.shortcuts(buf)
end

function M.setup()
  vim.on_key(function(_, typed)
    if typed:match("^[A-Za-z]$") then
      dismiss_alert()
      return
    end
    if typed == "" or M.english(typed) == typed then
      return
    end
    local ft = vim.bo.filetype
    if
      ft == "snacks_picker_input"
      or ft == "findbar"
      or vim.bo.buftype == "prompt"
      or vim.fn.keytrans(typed):find("<[DCMA]%-")
    then
      return
    end
    local mode = api.nvim_get_mode().mode:sub(1, 1)
    if mode == "n" or mode == "v" or mode == "V" or mode == "\22" then
      show_alert()
    end
  end, api.nvim_create_namespace("NonEnglishKeyboardAlert"))
  api.nvim_create_user_command("NonEnglishSearch", function(args)
    if args.args == "" or args.args == "toggle" then
      M.toggle()
    elseif args.args == "on" or args.args == "off" then
      M.toggle(args.args == "on")
    else
      vim.notify("Usage: NonEnglishSearch [on|off|toggle]", vim.log.levels.WARN)
    end
  end, {
    nargs = "?",
    complete = function()
      return { "on", "off", "toggle" }
    end,
  })
  local langmap = {}
  for character, english in pairs(letters) do
    langmap[#langmap + 1] = character .. english:gsub("([,;\\])", "\\%1")
  end
  table.sort(langmap)
  vim.opt.langmap:append(table.concat(langmap, ","))
  vim.o.langremap = false
  local group = api.nvim_create_augroup("NonEnglishKeyboard", { clear = true })
  api.nvim_create_autocmd({ "FileType", "BufEnter", "BufWinEnter" }, {
    group = group,
    callback = function(args)
      vim.schedule(function()
        M.attach(args.buf)
      end)
    end,
  })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LazyLoad",
    callback = vim.schedule_wrap(function()
      M.shortcuts()
      M.attach(api.nvim_get_current_buf())
    end),
  })
  api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = vim.schedule_wrap(function()
      M.shortcuts()
      M.attach(api.nvim_get_current_buf())
    end),
  })
end

return M
