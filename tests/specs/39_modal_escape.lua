local lib = require("lib")
local h = require("support")

lib.test("Escape is delivered to the topmost modal behind mouse focus", function()
  local screen = h.nvim(h.tmpdir())
  screen:exec([[
    vim.cmd("enew")
    local function modal(zindex, name)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { name })
      local win = vim.api.nvim_open_win(buf, false, {
        relative = "editor", row = 5, col = 30, width = 60, height = 20,
        border = "rounded", zindex = zindex,
      })
      vim.keymap.set("n", "<Esc>", function()
        vim.g["closed_" .. name] = true
        vim.api.nvim_win_close(win, true)
      end, { buffer = buf })
      return win
    end
    _G.lower_modal = modal(60, "lower")
    _G.upper_modal = modal(100, "upper")
  ]])
  screen:input("<Esc>")
  h.wait(screen, function()
    return screen:exec("return vim.g.closed_upper == true")
  end, "Escape did not reach the topmost modal")
  lib.ok(screen:exec("return vim.g.closed_lower ~= true"), "Escape reached a modal behind the topmost one")
  screen:close()
end)
