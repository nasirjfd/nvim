-- Text-field selection stays in Insert mode: typing, deletion and paste replace the range.
-- Buffer-local bindings only; never change the editor's global keymodel/selection options.
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("input-text-selection")
local states = {}

function M.clear(buf)
  local state = states[buf]
  if state then
    state.anchor = nil
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

local function range(buf)
  local state = states[buf]
  if not state or not state.anchor then
    return
  end
  local col = api.nvim_win_get_cursor(0)[2]
  if col ~= state.anchor then
    return math.min(col, state.anchor), math.max(col, state.anchor)
  end
end

local function erase(buf)
  local first, last = range(buf)
  M.clear(buf)
  if first then
    api.nvim_buf_set_text(buf, 0, first, 0, last, { "" })
    api.nvim_win_set_cursor(0, { 1, first })
    return true
  end
end

local function character(text, col, direction)
  if direction < 0 then
    local prefix = text:sub(1, col)
    return #prefix - #vim.fn.strcharpart(prefix, vim.fn.strchars(prefix) - 1, 1)
  end
  return col + #vim.fn.strcharpart(text:sub(col + 1), 0, 1)
end

local delete = {
  [vim.keycode("<BS>")] = true,
  [vim.keycode("<Del>")] = true,
  [vim.keycode("<C-w>")] = true,
  [vim.keycode("<C-u>")] = true,
}
vim.on_key(function(key, typed)
  local buf = api.nvim_get_current_buf()
  if not range(buf) or vim.fn.mode():sub(1, 1) ~= "i" then
    return
  end
  typed = typed ~= "" and typed or key
  if delete[typed] then
    erase(buf)
    return ""
  end
  if #typed > 0 and typed:byte(1) >= 32 and typed:byte(1) ~= 0x80 then
    erase(buf)
  elseif typed == vim.keycode("<CR>") or typed == vim.keycode("<Esc>") then
    M.clear(buf)
  end
end, api.nvim_create_namespace("input-text-selection-key"))

local paste = vim.paste
vim.paste = function(lines, phase)
  erase(api.nvim_get_current_buf())
  return paste(lines, phase)
end

function M.attach(buf)
  if states[buf] then
    return
  end
  states[buf] = {}
  api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      states[buf] = nil
    end,
  })
  local function move(direction, selecting, edge, word)
    local col = api.nvim_win_get_cursor(0)[2]
    local text = api.nvim_get_current_line()
    local first, last = range(buf)
    if selecting then
      states[buf].anchor = states[buf].anchor or col
    elseif first and not edge then
      col = direction < 0 and first or last
      M.clear(buf)
      api.nvim_win_set_cursor(0, { 1, col })
      return
    else
      M.clear(buf)
    end
    if edge then
      col = direction < 0 and 0 or #text
    elseif word then
      local function class(at)
        local char = vim.fn.strcharpart(text:sub(at + 1), 0, 1)
        return char:match("^%s$") and "space"
          or vim.fn.match(char, "\\k") >= 0 and "word"
          or "punctuation"
      end
      if direction < 0 then
        while col > 0 and class(character(text, col, -1)) == "space" do
          col = character(text, col, -1)
        end
        local kind = class(character(text, col, -1))
        while col > 0 and class(character(text, col, -1)) == kind do
          col = character(text, col, -1)
        end
      else
        local kind = class(col)
        while col < #text and class(col) == kind do
          col = character(text, col, 1)
        end
        while col < #text and class(col) == "space" do
          col = character(text, col, 1)
        end
      end
    else
      col = character(text, col, direction)
    end
    api.nvim_win_set_cursor(0, { 1, col })
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    first, last = range(buf)
    if first then
      api.nvim_buf_set_extmark(buf, ns, 0, first, { end_col = last, hl_group = "Visual" })
    end
  end
  for _, binding in ipairs({
    { "<Left>", -1 },
    { "<Right>", 1 },
    { "<Home>", -1, false, true },
    { "<End>", 1, false, true },
    { "<S-Left>", -1, true },
    { "<S-Right>", 1, true },
    { "<S-Home>", -1, true, true },
    { "<S-End>", 1, true, true },
    { "<D-S-Left>", -1, true, true },
    { "<D-S-Right>", 1, true, true },
    { "<S-Up>", -1, true, true },
    { "<S-Down>", 1, true, true },
    { "<M-S-Left>", -1, true, false, true },
    { "<M-S-Right>", 1, true, false, true },
    { "<C-S-Left>", -1, true, false, true },
    { "<C-S-Right>", 1, true, false, true },
  }) do
    vim.keymap.set("i", binding[1], function()
      move(binding[2], binding[3], binding[4], binding[5])
    end, {
      buffer = buf,
      silent = true,
      desc = binding[3] and "Extend text selection" or "Move in text",
    })
  end
  vim.keymap.set("i", "<D-a>", function()
    states[buf].anchor = 0
    move(1, true, true)
  end, { buffer = buf, desc = "Select all text" })
  for _, key in ipairs({ "<D-c>", "<D-x>" }) do
    vim.keymap.set("i", key, function()
      local first, last = range(buf)
      if first then
        vim.fn.setreg("+", api.nvim_get_current_line():sub(first + 1, last))
        if key == "<D-x>" then
          erase(buf)
        end
      end
    end, { buffer = buf, desc = key == "<D-x>" and "Cut selected text" or "Copy selected text" })
  end
end

return M
