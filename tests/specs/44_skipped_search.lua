local lib = require("lib")
local h = require("support")

local function fixture()
  local dir = h.repo({
    [".gitignore"] = { "ignored.txt" },
    ["src/Command/Test.php"] = { "base" },
  })
  h.git(dir, "update-index", "--skip-worktree", ".gitignore", "src/Command/Test.php")
  h.write(dir .. "/.gitignore", { "ignored.txt", "# skipped_search_marker" })
  h.write(dir .. "/src/Command/Test.php", { "skipped_search_marker" })
  h.write(dir .. "/ignored.txt", { "skipped_search_marker" })
  return dir
end

local function wait_results(screen, source, count)
  h.wait(screen, function()
    return screen:exec(
      [[
      local source, count = ...
      local p = Snacks.picker.get({ source = source })[1]
      return p and not p.finder:running() and not p.matcher:running() and p:count() == count
    ]],
      { source, count }
    )
  end, source .. " did not find the skipped files (or included ignored/Git files)")
end

lib.test("skipped files stay searchable and editable in cold and cached file search", function()
  local dir = fixture()
  local screen = h.nvim(dir)
  -- Isolate search/editing from PHP tooling (servers, parsers and formatters).
  screen:exec("vim.filetype.add({pattern = {['.*/Test%.php'] = 'text'}})")
  for _, cached in ipairs({ false, true }) do
    screen:exec(
      [[
      local cached = ...
      if cached then
        Snacks.picker.files(require('core.file-cache').opts())
      else
        Snacks.picker.files()
      end
    ]],
      { cached }
    )
    wait_results(screen, "files", 1)
    if not cached then
      screen:exec("require('core.file-cache').warm()")
      h.wait(screen, function()
        return screen:exec([[
          local p = Snacks.picker.get({source='files'})[1]
          local cache = require('core.file-cache')
          local items = cache.finder(vim.tbl_extend('force', p.opts, cache.opts()), p.finder:ctx(p))
          return type(items) == 'table' and #items == 1
        ]])
      end, "file cache did not warm with the skipped source file")
    else
      lib.ok(
        screen:exec([[
        return Snacks.picker.get({source='files'})[1]:items()[1]._cached_file == true
      ]]),
        "file search did not use the warmed cache"
      )
    end
    screen:exec([[
      local p = Snacks.picker.get({source='files'})[1]
      p.input:set('Test.php', 'Test.php'); p:find()
    ]])
    wait_results(screen, "files", 1)
    screen:input("<CR>")
    h.wait(screen, function()
      return screen:exec("return vim.fn.expand('%:t') == 'Test.php'")
    end, "skipped source file did not open for editing")
    screen:exec("vim.api.nvim_buf_set_lines(0, -1, -1, false, {'# edited'}); vim.cmd.write()")
  end
  lib.ok(
    h.git(dir, "ls-files", "-v", "src/Command/Test.php"):match("^S "),
    "editing removed skip-worktree"
  )
  lib.eq("", h.git(dir, "diff", "--name-only"), "skipped edits became Git changes")
  screen:close()
end)

lib.test("grep finds skipped files while keeping dotfiles and ignored files hidden", function()
  local dir = fixture()
  local screen = h.nvim(dir)
  screen:exec("Snacks.picker.grep({search='skipped_search_marker'})")
  wait_results(screen, "grep", 1)
  lib.eq(
    "src/Command/Test.php",
    screen:exec([[
    return Snacks.picker.get({source='grep'})[1]:items()[1].file
  ]]),
    "grep did not find the skipped source file"
  )
  lib.ok(
    h.git(dir, "ls-files", "-v", "src/Command/Test.php"):match("^S "),
    "search removed skip-worktree"
  )
  screen:close()
end)
