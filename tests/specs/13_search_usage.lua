local lib = require("lib")
local h = require("support")

-- Exercise Snacks' real persistent fallback store, isolated from the user's search history.
local function nvim(dir, history)
  return h.nvim(dir, nil, nil, { "-c", "lua " .. [[
    local kv = require('snacks.picker.util.kv')
    local new = kv.new
    kv.new = function(path, opts)
      if path:find('picker-frecency', 1, true) then path = ]] .. vim.inspect(history) .. [[ end
      return new(path, opts)
    end
    local db = require('snacks.picker.util.db')
    local db_new = db.new
    db.new = function(path, ...)
      if path:find('picker-frecency', 1, true) then error('use isolated fallback store') end
      return db_new(path, ...)
    end
  ]] })
end

local function visit_files(dir, history)
  local screen = nvim(dir, history)
  screen:exec([[
    vim.cmd('edit a_cold.lua')
    for _ = 1, 8 do
      vim.cmd('enew')
      vim.cmd('edit z_used.lua')
    end
    vim.cmd('enew')
  ]])
  screen:close() -- ExitPre must persist usage before the next Neovim starts
  lib.ok(vim.uv.fs_stat(history), "file usage was not saved on exit")
end

local function expect_first(screen, source, path)
  h.wait(screen, function()
    return screen:exec([[
      local source, file = ...
      local p = Snacks.picker.get({ source = source })[1]
      if not p or p.finder:running() or p.matcher:running() or p:count() ~= 2 then return false end
      local first = p.list:get(1)
      return first and vim.fs.basename(first.file) == file
    ]], { source, path })
  end, function()
    return "frequently opened file did not rank first in " .. source .. ": " .. vim.inspect(screen:exec([[
      local p = Snacks.picker.get({ source = ... })[1]
      local items = {}
      for i = 1, p.list:count() do
        local item = p.list:get(i)
        items[#items + 1] = { file = item.file, score = item.score, frecency = item.frecency }
      end
      return { items = items, matcher = p.matcher.opts }
    ]], { source }))
  end)
end

local function project()
  local dir = h.repo({
    ["a_cold.lua"] = { "-- needle" },
    ["z_used.lua"] = { "-- needle" },
  })
  return dir, dir .. "/history.dat"
end

lib.test("search usage: text results prefer frequently opened files after a Neovim restart", function()
  local dir, history = project()
  visit_files(dir, history)
  local screen = nvim(dir, history)
  screen:exec("Snacks.picker.grep({ search = 'needle' })")
  expect_first(screen, "grep", "z_used.lua")
  screen:close()
end)

lib.test("search usage: workspace symbols prefer frequently opened files after a Neovim restart", function()
  local dir, history = project()
  visit_files(dir, history)
  local screen = nvim(dir, history)
  screen:exec([[
    vim.cmd('enew')
    local dir = vim.fn.getcwd()
    require('snacks.picker.source.lsp').request = function(_, _, params, cb)
      local results = {}
      for _, file in ipairs({ 'a_cold.lua', 'z_used.lua' }) do
        results[#results + 1] = {
          name = 'MatchingSymbol', kind = 12,
          location = { uri = vim.uri_from_fname(dir .. '/' .. file), range = {
            start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 1 },
          } },
        }
      end
      cb({ offset_encoding = 'utf-16' }, results, params())
    end
    Snacks.picker.lsp_workspace_symbols()
  ]])
  expect_first(screen, "lsp_workspace_symbols", "z_used.lua")
  screen:close()
end)
