local lib = require("lib")
local h = require("support")

local function open_symbols(dir, files)
  local screen = h.nvim(dir)
  screen:exec([[
    local dir, files = ...
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/' .. files[1]))
    -- A deterministic LSP response, through the real Snacks symbol conversion and picker.
    require('snacks.picker.source.lsp').request = function(_, _, params, cb)
      local results = {}
      for i, file in ipairs(files) do
        results[#results + 1] = {
          name = 'Symbol' .. i, kind = 12,
          location = { uri = vim.uri_from_fname(dir .. '/' .. file), range = {
            start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 1 },
          } },
        }
      end
      cb({ offset_encoding = 'utf-16' }, results, params())
    end
  ]], { dir, files })
  screen:input("<Space>lS")
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'lsp_workspace_symbols' }) == 1")
  end, "workspace symbol picker did not open")
  return screen
end

local function expect(screen, names)
  table.sort(names)
  h.wait(screen, function()
    local found = screen:exec([[
      local p = Snacks.picker.get({ source = 'lsp_workspace_symbols' })[1]
      if not p or p.finder:running() then return {} end
      local out = {}
      for _, item in ipairs(p:items()) do out[#out + 1] = item.name end
      table.sort(out)
      return out
    ]])
    return vim.deep_equal(names, found)
  end, "unexpected symbol visibility; wanted " .. vim.inspect(names))
end

lib.test("workspace symbols: Option I and H independently reveal ignored and hidden files", function()
  local files = { "normal.lua", "ignored/file.lua", ".hidden/file.lua", ".hidden/ignored.lua" }
  local dir = h.repo({
    [".gitignore"] = { "ignored/", ".hidden/ignored.lua" },
    [files[1]] = { "function normal() end" },
    [files[2]] = { "function ignored() end" },
    [files[3]] = { "function hidden() end" },
    [files[4]] = { "function both() end" },
  })
  local screen = open_symbols(dir, files)
  expect(screen, { "Symbol1" })
  screen:exec([[
    local p = Snacks.picker.get({ source = 'lsp_workspace_symbols' })[1]
    p.input:set('Symbol', 'Symbol')
    p:find()
  ]])
  expect(screen, { "Symbol1" }) -- the symbol query is not a filename glob
  screen:input("<A-i>")
  expect(screen, { "Symbol1", "Symbol2" })
  screen:input("<A-h>")
  expect(screen, { "Symbol1", "Symbol2", "Symbol3", "Symbol4" })
  screen:input("<A-i>")
  expect(screen, { "Symbol1", "Symbol3" })
  screen:input("<A-h>")
  expect(screen, { "Symbol1" })
  screen:close()
end)

lib.test("workspace symbols: local .ignore overrides a parent's vendor ignore just like Find Files", function()
  local root = h.repo({ [".gitignore"] = { "vendor/*" } })
  local dir = root .. "/vendor"
  h.write(dir .. "/.ignore", { "!/pkg/", "!/pkg/**" })
  h.write(dir .. "/pkg/a.lua", { "function allowed() end" })
  h.write(dir .. "/other/a.lua", { "function ignored() end" })
  local screen = open_symbols(dir, { "pkg/a.lua", "other/a.lua" })
  expect(screen, { "Symbol1" })
  screen:input("<A-i>")
  expect(screen, { "Symbol1", "Symbol2" })
  screen:close()
end)
