local lib = require("lib")
local h = require("support")

local function fixture()
  local dir = h.repo({
    [".gitignore"] = { "ignored.txt" },
    ["config/local.yml"] = { "base" },
  })
  h.git(dir, "update-index", "--skip-worktree", ".gitignore", "config/local.yml")
  h.write(dir .. "/.gitignore", { "ignored.txt", "# skipped_search_marker" })
  h.write(dir .. "/config/local.yml", { "skipped_search_marker" })
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
    wait_results(screen, "files", 2)
    if not cached then
      screen:exec("require('core.file-cache').warm()")
      h.wait(screen, function()
        return screen:exec([[
          local p = Snacks.picker.get({source='files'})[1]
          local cache = require('core.file-cache')
          local items = cache.finder(vim.tbl_extend('force', p.opts, cache.opts()), p.finder:ctx(p))
          return type(items) == 'table' and #items == 2
        ]])
      end, "file cache did not warm with skipped dotfiles")
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
      p.input:set('.gitignore', '.gitignore'); p:find()
    ]])
    wait_results(screen, "files", 1)
    screen:input("<CR>")
    h.wait(screen, function()
      return screen:exec("return vim.fn.expand('%:t') == '.gitignore'")
    end, "skipped dotfile did not open for editing")
    screen:exec("vim.api.nvim_buf_set_lines(0, -1, -1, false, {'# edited'}); vim.cmd.write()")
  end
  lib.ok(h.git(dir, "ls-files", "-v", ".gitignore"):match("^S "), "editing removed skip-worktree")
  lib.eq("", h.git(dir, "diff", "--name-only"), "skipped edits became Git changes")
  screen:close()
end)

lib.test("grep finds skipped dotfiles without searching ignored files or Git internals", function()
  local dir = fixture()
  local screen = h.nvim(dir)
  screen:exec("Snacks.picker.grep({search='skipped_search_marker'})")
  wait_results(screen, "grep", 2)
  lib.ok(h.git(dir, "ls-files", "-v", ".gitignore"):match("^S "), "search removed skip-worktree")
  screen:close()
end)
