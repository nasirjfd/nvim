local lib = require("lib")
local h = require("support")

lib.test(
  "filename search ranks case-insensitive exact names above history and fuzzy matches",
  function()
    local files = {
      ["nested/Test.php"] = { "example" },
      ["nested/Order-Handler.ts"] = { "example" },
      ["nested/user_settings.json"] = { "example" },
      ["UpdateCustomerPaymentConfigCommandHandler.php"] = { "example" },
      ["Test.php.backup"] = { "example" },
      ["OtherOrder-Handler.ts"] = { "example" },
      ["OtherUser_Settings.json"] = { "example" },
      [".Test.php"] = { "example" },
    }
    local dir = h.repo(files)
    h.git(dir, "update-index", "--skip-worktree", "nested/Test.php")
    local screen = h.nvim(dir)
    screen:exec([[
    local rank = require('core.file-rank').on_match
    require('core.file-rank').on_match = function(matcher, item)
      rank(matcher, item)
      if not item.file:find('nested/', 1, true) then item.file_usage = 1000000 end
    end
  ]])
    for _, cached in ipairs({ false, true }) do
      screen:exec(
        [[
      if ... then Snacks.picker.files(require('core.file-cache').opts())
      else Snacks.picker.files() end
    ]],
        { cached }
      )
      h.wait(screen, function()
        return screen:exec("return #Snacks.picker.get({source='files'}) == 1")
      end, "file picker did not open")
      h.wait(screen, function()
        return screen:exec([[
          local p = Snacks.picker.get({source='files'})[1]
          return not p.finder:running() and not p.matcher:running() and p:count() == 7
        ]])
      end, "file search did not keep dotfiles hidden")
      if not cached then
        screen:exec("require('core.file-cache').warm()")
        h.wait(screen, function()
          return screen:exec([[
            local p = Snacks.picker.get({source='files'})[1]
            local cache = require('core.file-cache')
            local items = cache.finder(vim.tbl_extend('force', p.opts, cache.opts()), p.finder:ctx(p))
            return type(items) == 'table' and #items == 7
          ]])
        end, "filename search cache did not warm")
      else
        lib.ok(
          screen:exec([[
          return Snacks.picker.get({source='files'})[1]:items()[1]._cached_file == true
        ]]),
          "filename search did not use warmed cache"
        )
      end
      for _, name in ipairs({ "Test.php", "Order-Handler.ts", "user_settings.json" }) do
        screen:exec(
          [[
        local p = Snacks.picker.get({source='files'})[1]
        local q = ...; p.input:set(q, q); p:find()
      ]],
          { name:lower() }
        )
        h.wait(screen, function()
          return screen:exec(
            [[
          local p = Snacks.picker.get({source='files'})[1]
          return not p.finder:running() and not p.matcher:running()
            and p.list:get(1) and p.list:get(1).file == ...
        ]],
            { "nested/" .. name }
          )
        end, "exact filename was not first: " .. name)
      end
      screen:exec("Snacks.picker.get({source='files'})[1]:close()")
    end
    screen:close()
  end
)

local function resume_fixture()
  local lines = {}
  for i = 1, 200 do
    lines[i] = ("line %03d: enough text for a saved column"):format(i)
  end
  return h.repo({ ["last.txt"] = lines, ["explicit.txt"] = { "explicit" } })
end

local function save_view(dir, sidebar)
  local screen = h.nvim(dir)
  local view = screen:exec([[
    vim.cmd.edit('last.txt')
    vim.wo.wrap = false
    vim.api.nvim_win_set_cursor(0, {90, 12})
    vim.fn.winrestview({lnum=90, col=12, topline=75, leftcol=0})
    return vim.fn.winsaveview()
  ]])
  if sidebar then
    screen:exec("Snacks.explorer.open()")
    h.wait(screen, function()
      return screen:exec("return vim.bo.filetype == 'snacks_picker_list'")
    end, "explorer did not take focus")
  end
  screen:close()
  return view
end

for _, directory in ipairs({ false, true }) do
  lib.test(
    "restart restores last file, cursor and scroll with directory argument=" .. tostring(directory),
    function()
      local dir = resume_fixture()
      local view = save_view(dir, true)
      local screen = h.nvim(dir, nil, nil, directory and { "." } or nil)
      h.wait(screen, function()
        return screen:exec("return vim.fn.expand('%:t') == 'last.txt'")
      end, "last file was not restored")
      local restored = screen:exec("return vim.fn.winsaveview()")
      for _, key in ipairs({ "lnum", "col", "topline", "leftcol" }) do
        lib.eq(view[key], restored[key], "saved view differs: " .. key)
      end
      screen:close()
    end
  )
end

lib.test("restart respects an explicit file and tolerates a deleted last file", function()
  local dir = resume_fixture()
  save_view(dir)
  local screen = h.nvim(dir, nil, nil, { "explicit.txt" })
  lib.eq(
    "explicit.txt",
    screen:exec("return vim.fn.expand('%:t')"),
    "resume replaced explicit file"
  )
  screen:close()
  vim.fn.delete(dir .. "/explicit.txt")
  local missing = h.nvim(dir)
  lib.ok(missing:exec("return vim.fn.expand('%:t') ~= 'explicit.txt'"), "reopened deleted file")
  missing:close()
end)
