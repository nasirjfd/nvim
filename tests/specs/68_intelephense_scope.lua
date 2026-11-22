-- intelephense indexes only the packages the pickers show and what they depend on (lua/core/intelephense-scope.lua).
local lib = require("lib")
local h = require("support")

package.path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h") .. "/lua/?.lua;" .. package.path
local scope = require("core.intelephense-scope")

lib.test("intelephense scope: visible packages, what they require (recursively) and their own dev tools", function()
  local packages = {
    { name = "me/app", require = { ["lib/a"] = "*" }, ["require-dev"] = { ["phpunit/phpunit"] = "*" } },
    { name = "lib/a", require = { ["lib/b"] = "*" }, ["require-dev"] = { ["tool/x"] = "*" } },
    { name = "lib/b" },
    { name = "phpunit/phpunit", require = { ["lib/c"] = "*" } },
    { name = "lib/c" },
    { name = "tool/x" },
    { name = "other/admin", require = { ["lib/a"] = "*" } },
  }
  local keep = scope.closure(packages, { ["me/app"] = true })
  local names = vim.tbl_keys(keep)
  table.sort(names)
  lib.eq({ "lib/a", "lib/b", "lib/c", "me/app", "phpunit/phpunit" }, names,
    "a dependency's dev tools and packages nothing visible needs are left out")
end)

lib.test("intelephense scope: excludes what is neither visible nor needed, follows the .ignore", function()
  local root = vim.fn.resolve(h.tmpdir())
  local packages = {
    { name = "me/app", require = { ["lib/a"] = "*" } },
    { name = "lib/a" },
    { name = "other/admin" },
    { name = "other/big" },
  }
  for _, p in ipairs(packages) do
    h.write(root .. "/" .. p.name .. "/src/X.php", { "<?php" })
  end
  h.write(root .. "/composer/installed.json", { vim.json.encode({ packages = packages }) })
  -- the project shows only me/app: everything else is ignored (like supernova's vendor/* with exceptions)
  h.write(root .. "/.ignore", { "/*/", "!/me/", "/composer/" })
  local excludes = scope.excludes(root)
  local mine = vim.tbl_filter(function(g)
    return not vim.tbl_contains(scope.DEFAULTS, g)
  end, excludes)
  table.sort(mine)
  lib.eq({ root .. "/other/admin/**", root .. "/other/big/**" }, mine)
  lib.ok(vim.tbl_contains(excludes, "**/node_modules/**"), "intelephense's own defaults stay")
  -- a package added to the .ignore's exceptions is indexed from then on
  vim.uv.sleep(20) -- a newer mtime
  h.write(root .. "/.ignore", { "/*/", "!/me/", "!/other/", "/composer/" })
  local after = vim.tbl_filter(function(g)
    return not vim.tbl_contains(scope.DEFAULTS, g)
  end, scope.excludes(root))
  lib.eq({}, after, "other/* became visible: nothing excluded")
  lib.eq(nil, scope.excludes(h.tmpdir()), "no composer metadata: intelephense's defaults")
end)
