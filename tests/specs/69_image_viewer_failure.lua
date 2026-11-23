-- A PDF or image opened in a buffer is shown by Snacks' image viewer, which writes into the buffer (it clears it
-- while the image is shown, or puts the error there when the conversion fails) and left it modified: every Ctrl+Q
-- asked "Save changes to ….pdf?".
local lib = require("lib")
local h = require("support")

local function open(screen, file)
  -- as in Ghostty (kitty graphics): the tests' embedded UI has none, and the viewer would only print that
  screen:exec([[
    Snacks.image.supports = function() return true end
    Snacks.image.supports_terminal = function() return true end
    vim.cmd.edit(...)
  ]], { file })
end

lib.test("image viewer: a file it cannot convert shows the error and is not modified", function()
  local dir = h.tmpdir()
  h.write(dir .. "/broken.pdf", { "not a pdf at all" })
  local screen = h.nvim(dir)
  open(screen, "broken.pdf")
  h.wait(screen, function()
    return screen:exec("return (vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ''):find('Conversion Failed', 1, true) ~= nil")
  end, "the conversion error is not shown in the buffer")
  vim.wait(100) -- nothing else touches the buffer afterwards
  lib.eq(false, screen:exec("return vim.bo.modified"), "the PDF buffer is modified: quitting asks to save it")
  screen:close()
end)

lib.test("image viewer: a PDF it shows is not modified", function()
  if vim.fn.executable("magick") == 0 then
    error("ImageMagick is not installed: brew install imagemagick ghostscript (machine/check.sh)", 0)
  end
  local dir = h.tmpdir()
  vim.fn.system({ "magick", "-size", "40x40", "xc:red", dir .. "/page.pdf" })
  local screen = h.nvim(dir)
  open(screen, "page.pdf")
  h.wait(screen, function()
    return screen:exec([[
      -- the viewer has written into the buffer (cleared it while the image loads)
      return vim.bo.filetype == "image" and vim.b.changedtick > 2
    ]])
  end, "the PDF was not opened in the image viewer")
  vim.wait(300) -- the conversion and the drawing finish meanwhile
  lib.eq(false, screen:exec("return vim.bo.modified"), "the PDF buffer is modified: quitting asks to save it")
  screen:close()
end)
