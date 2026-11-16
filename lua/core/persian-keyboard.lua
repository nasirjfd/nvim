-- Keyboard-position translation, separate from optional Persian text shaping.
local M = {}
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
for persian, english in pairs(letters) do
  if persian ~= "ي" and persian ~= "ك" then
    physical[english] = persian
  end
end
local modes = { "n", "x", "o", "i", "s", "c", "t" }

function M.english(text)
  return (text:gsub("[\194-\244][\128-\191]+", letters))
end

local function search(buf)
  local ft = vim.bo[buf].filetype
  return ft == "snacks_picker_input" or (ft == "findbar" and api.nvim_win_get_cursor(0)[1] == 1)
end

function M.toggle(value)
  local enabled = value
  if enabled == nil then
    enabled = not vim.g.persian_search_english
  end
  vim.g.persian_search_english = enabled
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
  vim.notify("English search from Persian keyboard: " .. (enabled and "on" or "off"))
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
          desc = (mapping.desc or "Shortcut") .. " (Persian keyboard)",
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
    if not vim.b[buf].persian_search_keys then
      vim.b[buf].persian_search_keys = true
      for persian, english in pairs(letters) do
        vim.keymap.set({ "i", "s" }, persian, function()
          return vim.g.persian_search_english and search(buf) and english or persian
        end, {
          buffer = buf,
          expr = true,
          desc = "Optional English search from Persian keyboard",
        })
      end
      vim.keymap.set({ "i", "n", "s" }, "<C-S-l>", function()
        M.toggle()
      end, { buffer = buf, desc = "Toggle Persian keyboard English search" })
    end
  end
  M.shortcuts(buf)
end

function M.setup()
  api.nvim_create_user_command("PersianSearch", function(args)
    if args.args == "" or args.args == "toggle" then
      M.toggle()
    elseif args.args == "on" or args.args == "off" then
      M.toggle(args.args == "on")
    else
      vim.notify("Usage: PersianSearch [on|off|toggle]", vim.log.levels.WARN)
    end
  end, {
    nargs = "?",
    complete = function()
      return { "on", "off", "toggle" }
    end,
  })
  local langmap = {}
  for persian, english in pairs(letters) do
    langmap[#langmap + 1] = persian .. english:gsub("([,;\\])", "\\%1")
  end
  table.sort(langmap)
  vim.opt.langmap:append(table.concat(langmap, ","))
  vim.o.langremap = false
  local group = api.nvim_create_augroup("PersianKeyboard", { clear = true })
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
