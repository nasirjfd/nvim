-- A diagnostic jump owns one card until the user moves away, edits, or dismisses it.
-- Smooth scrolling and delayed CursorMoved events must not dismiss a newly opened card.
local M = {}
local api = vim.api
local active
local ns = api.nvim_create_namespace("DiagnosticCard")
local severities = {
  [vim.diagnostic.severity.ERROR] = { "", "Error", "DiagnosticError" },
  [vim.diagnostic.severity.WARN] = { "", "Warning", "DiagnosticWarn" },
  [vim.diagnostic.severity.INFO] = { "", "Info", "DiagnosticInfo" },
  [vim.diagnostic.severity.HINT] = { "󰌵", "Hint", "DiagnosticHint" },
}

local function close(state)
  state = state or active
  if not state or active ~= state then
    return
  end
  active = nil
  if state.group then
    api.nvim_del_augroup_by_id(state.group)
  end
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_win_close(state.win, true)
  end
  if api.nvim_buf_is_valid(state.buf) then
    vim.b[state.buf].snacks_scroll = state.scroll
  end
  if state.inline then
    require("tiny-inline-diagnostic").enable()
  end
end

local function begin(buf)
  close()
  local state = { buf = buf, owner = api.nvim_get_current_win(), scroll = vim.b[buf].snacks_scroll }
  active = state
  -- Keep the actual cursor at the diagnostic, not at an intermediate animation frame.
  vim.b[buf].snacks_scroll = false
  return state
end

function M.show(diagnostic, buf, state)
  if not diagnostic or api.nvim_get_current_buf() ~= buf then
    return
  end
  if state and active ~= state then
    return -- a newer jump already superseded this scheduled callback
  end
  if
    state and (not api.nvim_win_is_valid(state.owner) or api.nvim_get_current_win() ~= state.owner)
  then
    return
  end
  state = state or begin(buf)
  state.cursor = api.nvim_win_get_cursor(state.owner)

  -- Remove inline virtual lines before sizing/placing the card, not on the next redraw.
  -- Preserve a user-disabled display rather than turning it back on when the card closes.
  local inline = package.loaded["tiny-inline-diagnostic"]
  local inline_state = package.loaded["tiny-inline-diagnostic.state"]
  if inline and inline_state and inline_state.user_toggle_state then
    state.inline = true
    inline.disable()
    require("tiny-inline-diagnostic.extmarks").clear(buf)
  end

  local severity = severities[diagnostic.severity] or severities[vim.diagnostic.severity.INFO]
  local metadata = {}
  if diagnostic.source then
    metadata[#metadata + 1] = diagnostic.source
  end
  if diagnostic.code then
    metadata[#metadata + 1] = tostring(diagnostic.code)
  end
  local lines = { "  " .. table.concat(metadata, "  ·  "), " " }
  for _, line in ipairs(vim.split(diagnostic.message, "\n", { plain = true })) do
    lines[#lines + 1] = "  " .. line .. "  "
  end
  lines[#lines + 1] = " "
  local width = 44
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.max(1, math.min(width, 88, api.nvim_win_get_width(state.owner) - 4))
  local card_buf, win = vim.lsp.util.open_floating_preview(lines, "plaintext", {
    focus = false,
    border = "rounded",
    title = { { " " .. severity[1] .. "  " .. severity[2] .. " ", severity[3] } },
    title_pos = "left",
    width = width,
    max_height = math.max(1, math.min(18, api.nvim_win_get_height(state.owner) - 4)),
    close_events = {}, -- owned below: a queued CursorMoved at the same position is harmless
  })
  state.win = win
  vim.bo[card_buf].filetype = "diagnostic_card"
  vim.wo[win].winhighlight = "NormalFloat:NormalFloat,FloatBorder:" .. severity[3]
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  api.nvim_win_set_config(win, {
    footer = { { " [d / ]d  navigate  ·  Esc close ", "Comment" } },
    footer_pos = "right",
  })
  api.nvim_buf_set_extmark(card_buf, ns, 0, 0, { end_col = #lines[1], hl_group = "Comment" })

  state.group = api.nvim_create_augroup("DiagnosticCardLifetime", { clear = true })
  api.nvim_create_autocmd("WinClosed", {
    group = state.group,
    pattern = tostring(win),
    callback = function()
      state.win = nil -- WinClosed runs while the window is still being torn down
      close(state)
    end,
  })
  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = state.group,
    buffer = buf,
    callback = function()
      if
        api.nvim_win_is_valid(state.owner)
        and not vim.deep_equal(api.nvim_win_get_cursor(state.owner), state.cursor)
      then
        close(state)
      end
    end,
  })
  api.nvim_create_autocmd({ "InsertEnter", "TextChanged", "BufHidden" }, {
    group = state.group,
    buffer = buf,
    callback = function()
      close(state)
    end,
  })
  api.nvim_create_autocmd({ "WinEnter", "TabEnter" }, {
    group = state.group,
    callback = function()
      local current = api.nvim_get_current_win()
      if current ~= state.owner and current ~= state.win then
        close(state)
      end
    end,
  })
end

function M.jump(count)
  local state = begin(api.nvim_get_current_buf())
  vim.diagnostic.jump({
    count = count,
    on_jump = function(diagnostic, buf)
      M.show(diagnostic, buf, state)
    end,
  })
  vim.schedule(function()
    if active == state and not state.win then
      close(state) -- no diagnostics, or the buffer changed before the jump callback
    end
  end)
end

function M.setup()
  for key, direction in pairs({ ["[d"] = -1, ["]d"] = 1 }) do
    vim.keymap.set("n", key, function()
      M.jump(direction * vim.v.count1)
    end, { silent = true, desc = direction == 1 and "Next Diagnostic" or "Prev Diagnostic" })
  end
end

return M
