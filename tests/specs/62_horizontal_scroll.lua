-- Option+l / Option+h scroll the view right / left like zl / zh, the cursor staying on its column.
local lib = require("lib")
local h = require("support")

lib.test("Option+l and Option+h scroll sideways without moving the cursor", function()
  local dir = h.tmpdir()
  h.write(dir .. "/long.txt", { string.rep("abcdefghij", 40) })
  local screen = h.nvim(dir, 80, 20)
  screen:exec("vim.cmd('edit long.txt'); vim.api.nvim_win_set_cursor(0, {1, 40})")
  local function view()
    return screen:exec("local v = vim.fn.winsaveview() return { v.leftcol, v.col, vim.fn.mode() }")
  end
  for _, mode in ipairs({ "normal", "visual", "insert" }) do
    screen:exec("vim.fn.winrestview({ leftcol = 0 }); vim.api.nvim_win_set_cursor(0, {1, 40})")
    if mode == "visual" then
      screen:input("v")
    elseif mode == "insert" then
      screen:input("i")
    end
    local mode_char = ({ normal = "n", visual = "v", insert = "i" })[mode]
    screen:input("<M-l><M-l><M-l><M-l><M-l>")
    h.wait(screen, function()
      return vim.deep_equal(view(), { 5, 40, mode_char })
    end, mode .. ": Option+l did not scroll right 5 with the cursor kept: " .. vim.inspect(view()))
    screen:input("<M-h><M-h>")
    h.wait(screen, function()
      return vim.deep_equal(view(), { 3, 40, mode_char })
    end, mode .. ": Option+h did not scroll left 2 with the cursor kept: " .. vim.inspect(view()))
    screen:input("<Esc>")
  end
  lib.eq({ string.rep("abcdefghij", 40) }, screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
  screen:close()
end)
