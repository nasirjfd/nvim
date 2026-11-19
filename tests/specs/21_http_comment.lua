local lib = require("lib")
local h = require("support")

lib.test("Cmd+/ in a .http file: # on request lines, // inside the JSON body", function()
  local dir = h.repo({
    ["a.http"] = {
      "### x",
      "POST https://a.b/c",
      "Content-Type: application/json",
      "",
      "{",
      '  "a": 1',
      "}",
    },
  })
  local screen = h.nvim(dir)
  screen:exec(("vim.cmd.edit(%q)"):format(dir .. "/a.http"))
  local function comment(line)
    screen:exec(("vim.api.nvim_win_set_cursor(0, { %d, 0 })"):format(line))
    screen:exec([[require("Comment.api").toggle.linewise.current()]])
  end
  h.wait(screen, function()
    return screen:exec([[
      local p = vim.treesitter.get_parser(0); p:parse(true)
      return p:language_for_range({ 5, 2, 5, 3 }):lang() == "json"
    ]])
  end, "json body was not parsed")
  comment(2)
  comment(6)
  h.wait(screen, function()
    local lines = screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
    return lines[2] == "# POST https://a.b/c" and lines[6] == '  // "a": 1'
  end, function()
    return vim.inspect(screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
  end)
  screen:close()
end)
