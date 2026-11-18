-- Helpers shared by the specs: throwaway directories / git repositories and an embedded Neovim.
local Screen = require("screen")
local lib = require("lib")
local M = {}

local open_screens = {}
lib.on_cleanup(function()
  for _, screen in ipairs(open_screens) do
    pcall(screen.close, screen)
  end
  open_screens = {}
end)

function M.tmpdir()
  local dir = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(dir, "p")
  return dir
end

function M.write(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines, path)
end

function M.read(path)
  return vim.fn.readfile(path)
end

function M.git(dir, ...)
  local out = vim.fn.system(
    vim.list_extend({ "git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@t" }, { ... })
  )
  assert(vim.v.shell_error == 0, "git failed: " .. out)
  return out
end

function M.repo(files)
  local dir = M.tmpdir()
  M.git(dir, "init", "-q", "-b", "main")
  for name, lines in pairs(files) do
    M.write(dir .. "/" .. name, lines)
  end
  M.git(dir, "add", ".")
  M.git(dir, "commit", "-q", "-m", "base")
  return dir
end

-- An embedded Neovim running this configuration in `cwd`, ready for input.
function M.nvim(cwd, width, height, extra_args)
  local screen = Screen.new(width or 160, height or 45, cwd, extra_args)
  open_screens[#open_screens + 1] = screen
  screen:await(function()
    return screen:exec("return vim.v.vim_did_enter == 1")
  end, "Neovim did not start", 15000)
  -- the configuration's startup output (notifications) has nothing to do with what is tested
  screen:exec("pcall(function() Snacks.notifier.hide() end)")
  return screen
end

-- 1-based screen column of the first cell run spelling `text` on `row`, or nil
function M.find_on_row(screen, row, text)
  local chars = vim.fn.split(text, "\\zs")
  for col = 1, screen.width - #chars + 1 do
    local hit = true
    for i, ch in ipairs(chars) do
      if screen.grid[row][col + i - 1][1] ~= ch then
        hit = false
        break
      end
    end
    if hit then
      return col
    end
  end
end

-- the first screen row (1-based) that has `text`, and its column; `max_col`: only look at the columns up to it
-- (e.g. the sidebar, not the file next to it)
function M.find_on_screen(screen, text, max_col)
  for row = 1, screen.height do
    local col = M.find_on_row(screen, row, text)
    if col and (not max_col or col <= max_col) then
      return row, col
    end
  end
end

function M.row_text(screen, row)
  return screen:text(row, 1, screen.width)
end

function M.mouse(screen, action, row, col)
  screen:request("nvim_input_mouse", { "left", action, "", 0, row - 1, col - 1 })
end

function M.click(screen, row, col)
  M.mouse(screen, "press", row, col)
  M.mouse(screen, "release", row, col)
end

function M.hover(screen, row, col)
  screen:request("nvim_input_mouse", { "move", "", "", 0, row - 1, col - 1 })
end

-- Poll `predicate` until it is true. It is polled from a plain loop, never from inside vim.wait, because
-- the predicates talk to the embedded Neovim (a request is itself a vim.wait).
-- What the embedded editor shows and its last messages: printed with a failed wait, so one failing run is
-- enough to see why.
function M.snapshot(screen)
  local rows = {}
  for r = 1, screen.height or 0 do
    local cells = screen.grid and screen.grid[r]
    if cells then
      local text = {}
      for c = 1, screen.width do
        text[#text + 1] = cells[c] and cells[c][1] or " "
      end
      rows[#rows + 1] = (table.concat(text):gsub("%s+$", ""))
    end
  end
  local ok, messages = pcall(function()
    return screen:exec("return vim.fn.execute('messages')")
  end)
  local tail = ok
      and type(messages) == "string"
      and table.concat(
        vim.list_slice(vim.split(messages, "\n"), math.max(1, #vim.split(messages, "\n") - 8)),
        "\n"
      )
    or "(no messages)"
  return "--- screen ---\n" .. table.concat(rows, "\n") .. "\n--- messages ---\n" .. tail
end

-- A wait returns as soon as its condition holds, so a generous limit costs nothing when things go well
-- and keeps a busy machine (parallel workers) from failing a test that is only slow.
function M.wait(screen, predicate, message, timeout)
  local deadline = vim.uv.hrtime() + (timeout or 15000) * 1e6
  while true do
    assert(not screen.error, tostring(screen.error))
    if predicate() then
      screen:flush()
      return
    end
    if vim.uv.hrtime() > deadline then
      error(
        (type(message) == "function" and message() or message)
          .. "\n"
          .. screen.stderr
          .. "\n"
          .. M.snapshot(screen),
        2
      )
    end
    vim.wait(20)
  end
end

return M
