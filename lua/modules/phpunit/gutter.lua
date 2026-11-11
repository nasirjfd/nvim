-- Click the icon in the gutter of a test (✓ ✗ or the plain test icon neotest shows) to run that test again.
--
-- A global <LeftMouse> mapping: a click in the sign/number area of a line that has a test sign runs the test and
-- is swallowed; any other click does what it always did (the mapping returns the key itself, not remapped).
local M = {}

local function sign_line(buf, line)
  -- neotest's own signs
  local placed = vim.fn.sign_getplaced(buf, { group = "neotest-status", lnum = line })[1]
  if placed and #placed.signs > 0 then
    return true
  end
  -- the failure sign of messages.lua
  local ns = require("modules.phpunit.messages").namespace
  return #vim.api.nvim_buf_get_extmarks(buf, ns, { line - 1, 0 }, { line - 1, -1 }, {}) > 0
end

--- Whether the click at the mouse position is on a test's gutter icon; runs the test when it is.
function M.click()
  if not package.loaded["neotest"] then
    return false
  end
  local mouse = vim.fn.getmousepos()
  if mouse.winid == 0 or mouse.line <= 0 or not vim.api.nvim_win_is_valid(mouse.winid) then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(mouse.winid)
  if vim.bo[buf].buftype ~= "" then
    return false
  end
  local info = vim.fn.getwininfo(mouse.winid)[1]
  if not info or mouse.wincol > info.textoff then
    return false -- a click in the text
  end
  if not sign_line(buf, mouse.line) then
    return false
  end
  local file = vim.api.nvim_buf_get_name(buf)
  vim.schedule(function()
    require("modules.phpunit.runner").run_at(file, mouse.line - 1)
  end)
  return true
end

function M.setup()
  vim.keymap.set("n", "<LeftMouse>", function()
    if M.click() then
      return ""
    end
    return "<LeftMouse>"
  end, { expr = true, replace_keycodes = true, desc = "Run the test of a gutter icon" })
end

return M
