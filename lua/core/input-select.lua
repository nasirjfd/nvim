-- A prompt (vim.ui.input / Snacks.input) that opens with text shows it selected, like a selected text
-- field: the first key decides. A character or a paste replaces the text, Backspace / Ctrl+W / Ctrl+U
-- clear it, anything else (Enter, arrows, Home/End) keeps it as text. Handled in vim.on_key, before
-- the key runs, so keys typed faster than the screen updates (a paste and Enter at once) stay in
-- order. Attached to every Snacks input (lua/plugins/input-navigation.lua): the commit message (the
-- branch's last one), a branch to rename, a suggested variable name, a symbol to rename.
local M = {}
local api = vim.api

M.ns = api.nvim_create_namespace("input-default-selection")
local key_ns = api.nvim_create_namespace("input-default-selection-key")
local CLEAR = { [vim.keycode("<BS>")] = true, [vim.keycode("<C-w>")] = true, [vim.keycode("<C-u>")] = true }

function M.attach(buf)
  if not api.nvim_buf_is_valid(buf) or vim.b[buf].input_default_selection then
    return
  end
  local default = api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
  if default == "" or api.nvim_buf_line_count(buf) > 1 then
    return
  end
  vim.b[buf].input_default_selection = true
  local ns = M.ns
  api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = #default, hl_group = "Visual" })
  local listener, paste
  local active = true -- turned off at the first key: done() itself runs after the key
  local function done()
    active = false
    vim.on_key(nil, listener)
    if paste and vim.paste == paste.wrapper then
      vim.paste = paste.original
    end
    paste = nil
    if api.nvim_buf_is_valid(buf) then
      api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end
  listener = vim.on_key(function(key, typed)
    if not active then
      return
    end
    typed = typed ~= "" and typed or key
    if not api.nvim_buf_is_valid(buf) or api.nvim_get_current_buf() ~= buf then
      active = false
      return vim.schedule(done)
    end
    if vim.fn.mode() ~= "i" then
      return
    end
    local clear = CLEAR[typed]
    local char = not clear and #typed >= 1 and typed:byte(1) >= 32 and typed:byte(1) ~= 0x80
    if
      (clear or char)
      and api.nvim_buf_get_lines(buf, 0, 1, false)[1] == default
      and api.nvim_win_get_cursor(0)[2] == #default
    then
      active = false
      api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
      api.nvim_win_set_cursor(0, { 1, 0 })
      vim.schedule(done)
      return clear and "" or nil -- the clearing key itself is spent
    end
    active = false
    vim.schedule(done)
  end, key_ns)
  -- A terminal paste (Cmd+V) does not pass through on_key: it replaces the text as well.
  paste = { original = vim.paste }
  paste.wrapper = function(lines, phase)
    local original = paste and paste.original or vim.paste
    if
      active
      and api.nvim_get_current_buf() == buf
      and api.nvim_buf_get_lines(buf, 0, 1, false)[1] == default
      and (phase == -1 or phase == 1)
    then
      api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
      api.nvim_win_set_cursor(0, { 1, 0 })
    end
    done()
    return original(lines, phase)
  end
  vim.paste = paste.wrapper
  api.nvim_create_autocmd("BufLeave", { buffer = buf, once = true, callback = done })
end

return M
