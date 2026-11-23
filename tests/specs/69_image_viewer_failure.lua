-- A PDF or image the viewer cannot convert (no ImageMagick on the machine, a broken file) shows the error in its
-- buffer. Snacks left that buffer modified, so every Ctrl+Q asked "Save changes to ….pdf?".
local lib = require("lib")
local h = require("support")

lib.test("image viewer: a file it cannot convert shows the error and is not modified", function()
  local dir = h.tmpdir()
  h.write(dir .. "/broken.pdf", { "not a pdf at all" })
  local screen = h.nvim(dir)
  -- as in Ghostty (kitty graphics): the tests' embedded UI has none, and the viewer would only print that
  screen:exec([[
    Snacks.image.supports = function() return true end
    Snacks.image.supports_terminal = function() return true end
    vim.cmd.edit("broken.pdf")
  ]])
  h.wait(screen, function()
    return screen:exec("return (vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ''):find('Conversion Failed', 1, true) ~= nil")
  end, "the conversion error is not shown in the buffer")
  vim.wait(100) -- nothing else touches the buffer afterwards
  lib.eq(false, screen:exec("return vim.bo.modified"), "the PDF buffer is modified: quitting asks to save it")
  screen:close()
end)
