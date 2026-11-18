local lib = require("lib")
local h = require("support")

lib.test(
  "grep rows preserve long filenames instead of spending their width on paths and matched text",
  function()
    local dir = h.tmpdir()
    local name = "PointAnnouncedThatReceivedParcelTheRideReportedAsNotPickedUp.php"
    local longer =
      "AnEvenLongerFilenameThatMustRemainWholeWhenTheMatchingSourceLineIsMuchTooLongToFit.php"
    h.write(dir .. "/digiexpress/point-provider-contract/src/Message/Event/" .. name, {
      "needle " .. string.rep("some long matching source text ", 12),
    })
    h.write(dir .. "/very/long/nested/directory/" .. longer, {
      "needle " .. string.rep("another long matching source text ", 12),
    })
    local screen = h.nvim(dir, 180, 45)
    screen:exec("Snacks.picker.grep({search='needle'})")
    h.wait(screen, function()
      return screen:exec([[
      local p=Snacks.picker.get({source='grep'})[1]
      return p and not p.finder:running() and not p.matcher:running() and p:count()==2
    ]])
    end, "grep did not settle")
    local lines = screen:exec([[
    local p=Snacks.picker.get({source='grep'})[1]
    return vim.api.nvim_buf_get_lines(p.list.win.buf,0,-1,false)
  ]])
    for _, file in ipairs({ name, longer }) do
      local found = false
      for _, line in ipairs(lines) do
        found = found or line:find(file, 1, true) ~= nil
      end
      lib.ok(found, "filename was truncated in the results list (not the preview): " .. file)
      -- Check actual list screen cells too: an untruncated buffer line alone is
      -- insufficient if the filename is horizontally clipped off the window.
      lib.ok(h.find_on_screen(screen, file), "full filename is not visible: " .. file)
    end
    screen:close()
  end
)
