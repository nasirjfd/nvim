local lib = require("lib")
local h = require("support")

local function commit_prompt()
  local dir = h.repo({ ["a.txt"] = { "before" } })
  h.write(dir .. "/a.txt", { "after" })
  h.git(dir, "add", "a.txt")
  local screen = h.nvim(dir)
  screen:exec([[
    _G.commit_calls = {}
    _G.commit_notes = {}
    vim.notify = function(msg) table.insert(_G.commit_notes, msg) end
    require('codediff.core.git').commit = function(root, message)
      table.insert(_G.commit_calls, {root, message})
    end
    vim.cmd('CodeDiff scm')
  ]])
  h.wait(screen, function()
    return screen:exec([[
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      if not p or not p.tree then return false end
      for line=1,vim.api.nvim_buf_line_count(p.bufnr) do
        local node = p.tree:get_node(line)
        if node and node.data and node.data.path == 'a.txt' then
          vim.api.nvim_set_current_win(p.winid)
          vim.api.nvim_win_set_cursor(p.winid, {line, 0})
          return true
        end
      end
      return false
    ]])
  end, "staged file did not load in Git")
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      return s and s.refresh and not s.refresh.loading and not s.refresh.running
    ]])
  end, "Git view did not finish loading")
  screen:input("c")
  h.wait(screen, function()
    return screen:exec(
      "return vim.bo.filetype == 'snacks_input' and vim.fn.mode() == 'i' and vim.b.mac_input_navigation == true"
    )
  end, function()
    return "commit message prompt did not open: "
      .. vim.inspect(screen:exec([[
      return {notes=_G.commit_notes, ft=vim.bo.filetype, mode=vim.fn.mode(), attached=vim.b.mac_input_navigation,
        title=vim.api.nvim_win_get_config(0).title, messages=vim.api.nvim_exec2('messages',{output=true}).output,
        input=vim.inspect(Snacks.config.input.win), map=vim.inspect(vim.fn.maparg('c','n',false,true))}
    ]]))
  end)
  screen:exec("_G.commit_input_buf = vim.api.nvim_get_current_buf()")
  screen:input("fix payment retry handling")
  return screen
end

local function position(screen, col)
  h.wait(screen, function()
    return screen:exec(
      [[
      return vim.api.nvim_get_current_buf() == _G.commit_input_buf and vim.fn.mode() == 'i'
        and vim.api.nvim_win_get_cursor(0)[2] == ... and #_G.commit_calls == 0
    ]],
      { col }
    )
  end, "navigation moved incorrectly, left Insert mode, or closed/submitted the commit prompt")
end

for _, keys in ipairs({
  { name = "Option arrows", left = "<M-Left>", right = "<M-Right>" },
  { name = "terminal Meta keys", left = "<M-b>", right = "<M-f>" },
  { name = "legacy Escape prefixes", left = "<Esc>b", right = "<Esc>f" },
}) do
  lib.test(
    "commit message supports repeated " .. keys.name .. " and Cmd arrows without closing",
    function()
      local screen = commit_prompt()
      position(screen, 26)
      for _, col in ipairs({ 18, 12, 4, 0, 0, 0 }) do
        screen:input(keys.left)
        position(screen, col)
      end
      for _, col in ipairs({ 4, 12, 18, 26, 26, 26 }) do
        screen:input(keys.right)
        position(screen, col)
      end
      screen:input("<D-Left>")
      position(screen, 0)
      screen:input("<D-Right>")
      position(screen, 26)
      lib.eq("fix payment retry handling", screen:exec("return vim.api.nvim_get_current_line()"))
      screen:input("<CR>")
      h.wait(screen, function()
        return screen:exec(
          "return #_G.commit_calls == 1 and _G.commit_calls[1][2] == 'fix payment retry handling'"
        )
      end, "Enter no longer submits the commit message")
      screen:close()
    end
  )
end

lib.test(
  "commit message handles split terminal Option arrows and still supports Escape cancellation",
  function()
    local screen = commit_prompt()
    position(screen, 26)
    for _, col in ipairs({ 18, 12, 4, 0, 0 }) do
      screen:exec("vim.defer_fn(function() vim.api.nvim_input('b') end, 30)")
      screen:input("<Esc>")
      position(screen, col)
    end
    screen:input("<Esc>")
    local ok, err = pcall(h.wait, screen, function()
      return screen:exec(
        "return vim.api.nvim_get_current_buf() ~= _G.commit_input_buf and #_G.commit_calls == 0 and vim.fn.mode() == 'n'"
      )
    end, "one Escape did not cancel the prompt")
    lib.ok(ok, tostring(err) .. " stderr: " .. screen.stderr)
    screen:close()
  end
)
