local lib = require("lib")
local h = require("support")

local function editor(dir, state)
  return h.nvim(
    dir,
    nil,
    nil,
    { "--cmd", "lua vim.env.XDG_STATE_HOME = " .. string.format("%q", state) }
  )
end

lib.test("HTTP clone picker cancellation leaves the destination unchanged", function()
  local dir = h.tmpdir()
  local original = { "### Request", "GET https://example.com" }
  h.write(dir .. "/request.http", original)
  local screen = editor(dir, h.tmpdir())
  screen:exec("vim.cmd('edit request.http')")
  screen:input("<Space>kc")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'snacks_picker_input'")
  end, "clone picker did not open")
  screen:input("<Esc>")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'http'")
  end, "clone picker did not close")
  lib.eq(original, screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
  screen:close()
end)

lib.test(
  "HTTP clone picker inserts a full request at the captured cursor without changing its source",
  function()
    local dir = h.tmpdir()
    h.write(dir .. "/source.http", {
      "### Source",
      "# @name source",
      "POST https://example.com",
      "Content-Type: application/json",
      "",
      '{"value": 1}',
    })
    h.write(dir .. "/target.http", { "### Existing", "GET https://example.com/existing", "", "" })
    local screen = editor(dir, h.tmpdir())
    screen:exec("vim.cmd('edit target.http'); vim.api.nvim_win_set_cursor(0, { 4, 0 })")
    screen:input("<Space>kc")
    h.wait(screen, function()
      return screen:exec("return vim.bo.filetype == 'snacks_picker_input'")
    end, "clone picker did not open")
    screen:input("source")
    h.wait(screen, function()
      return screen:exec([[
      local p = Snacks.picker.get()[1]
      return p and p:current() and p:current().name == "source"
    ]])
    end, "source request did not filter")
    screen:input("<CR>")
    h.wait(screen, function()
      return screen:exec("return vim.bo.filetype == 'http' and vim.api.nvim_buf_line_count(0) > 4")
    end, "clone was not inserted")
    local lines = screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
    lib.eq({
      "### Source",
      "# @name source",
      "POST https://example.com",
      "Content-Type: application/json",
      "",
      '{"value": 1}',
    }, vim.list_slice(lines, 4, 9))
    lib.eq({
      "### Source",
      "# @name source",
      "POST https://example.com",
      "Content-Type: application/json",
      "",
      '{"value": 1}',
    }, h.read(dir .. "/source.http"))
    screen:input("u")
    h.wait(screen, function()
      return screen:exec("return vim.api.nvim_buf_line_count(0) == 4")
    end, "clone was not a single undo step")
    screen:close()
  end
)

lib.test(
  "Kulala remembers selected environments across sessions and keeps projects separate",
  function()
    local dir, state = h.tmpdir(), h.tmpdir()
    h.write(dir .. "/a/request.http", { "GET https://example.com" })
    h.write(dir .. "/a/http-client.env.json", { '{"dev": {}, "prod": {}}' })
    h.write(dir .. "/b/request.http", { "GET https://example.com" })
    h.write(dir .. "/b/http-client.env.json", { '{"stage": {}}' })
    local screen = editor(dir, state)
    screen:exec("vim.cmd('edit a/request.http'); vim.g.kulala_selected_env = 'prod'")
    screen:exec("vim.cmd('edit b/request.http'); vim.g.kulala_selected_env = 'stage'")
    screen:close()
    screen = editor(dir, state)
    screen:exec("vim.cmd('edit a/request.http')")
    lib.eq("prod", screen:exec("return vim.g.kulala_selected_env"))
    screen:exec("vim.cmd('edit b/request.http')")
    lib.eq("stage", screen:exec("return vim.g.kulala_selected_env"))
    screen:close()
  end
)

lib.test(
  "Kulala response stays focusable but closes when switching to a non-HTTP editor file",
  function()
    local dir = h.tmpdir()
    h.write(dir .. "/request.http", { "GET https://example.com" })
    h.write(dir .. "/notes.txt", { "notes" })
    local screen = editor(dir, h.tmpdir())
    screen:exec([[
    vim.cmd("edit request.http")
    _G.request_win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, require("kulala.globals").UI_ID)
    _G.response_win = vim.api.nvim_open_win(buf, true, { split = "right", win = _G.request_win })
  ]])
    vim.wait(100)
    lib.ok(
      screen:exec("return vim.api.nvim_win_is_valid(_G.response_win)"),
      "response closed on focus"
    )
    screen:exec("vim.api.nvim_set_current_win(_G.request_win); vim.cmd('edit notes.txt')")
    h.wait(screen, function()
      return screen:exec("return not vim.api.nvim_win_is_valid(_G.response_win)")
    end, "response did not close on non-HTTP file switch")
    screen:close()
  end
)
