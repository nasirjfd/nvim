-- Pickers show the whole file name; only the folder part is ever shortened.
local lib = require("lib")
local h = require("support")

lib.test("picker rows keep a long file name whole and shorten the folders", function()
  local dir = h.tmpdir()
  local name = "VeryLongNamedClassForTestingTruncationOfFileNamesDTOExtra.php"
  h.write(dir .. "/deep/dir/with/many/levels/here/" .. name, { "class VeryLongNamedClassForTestingTruncationOfFileNamesDTOExtra extends SomethingElseEntirely implements AndAnotherVeryLongInterface {}" })
  local screen = h.nvim(dir, 100, 40)
  screen:exec("Snacks.picker.grep({ cwd = ... })", { dir })
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'grep' }) == 1")
  end, "the grep picker never opened")
  screen:input("VeryLongNamed")
  h.wait(screen, function()
    return h.find_on_screen(screen, name) ~= nil
  end, "the full file name is not on the screen")
  -- the setting that keeps a name whole when the row is crowded by a long matched line (a narrow path
  -- column cut "…lInPersonReceive…" from the front of the name)
  local min_width = screen:exec("return Snacks.config.picker.formatters.file.min_width")
  lib.ok(min_width and min_width >= 70, "the path column may shrink to " .. tostring(min_width))
  screen:close()
end)
