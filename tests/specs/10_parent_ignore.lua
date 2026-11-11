-- A folder the parent repo ignores (supernova's vendor/ with `vendor/*`): the pickers inside it list
-- only what the parent allows plus what a local `.ignore` in the folder unignores (fd and rg read it
-- before the parent's .gitignore). Nothing else is loaded by default, so searching stays fast.
local lib = require("lib")
local h = require("support")

local function vendor()
  local root = h.tmpdir()
  h.git(root, "init", "-q", "-b", "main")
  h.write(root .. "/.gitignore", { "vendor/*" })
  local name = "RequestRouteCapacitiesForMassDescriptionsCommand"
  h.write(root .. "/vendor/.ignore", { "!/pkg/", "!/pkg/**" })
  h.write(root .. "/vendor/pkg/src/" .. name .. ".php", { "<?php", "final class " .. name .. " {}" })
  h.write(root .. "/vendor/other/src/NotUnignored.php", { "<?php", "final class NotUnignored {}" })
  return root .. "/vendor", name
end

-- the picker's items, once the search has settled
local function results(screen, source, text)
  screen:exec("local src, q = ...; local p = Snacks.picker.get({ source = src })[1]; p.input:set(q, q); p:find()", { source, text })
  h.wait(screen, function()
    return screen:exec("local p = Snacks.picker.get({ source = ... })[1]; return p and p:count() or 0", { source }) > 0
  end, source .. " found nothing for " .. text)
  screen:exec("vim.wait(500)")
  return screen:exec(
    "local out = {}; for _, it in ipairs(Snacks.picker.get({ source = ... })[1]:items()) do out[#out + 1] = it.file end return out",
    { source }
  )
end

local function only_unignored(files, name)
  lib.eq(1, #files, "only the unignored package is listed, got: " .. table.concat(files, ", "))
  lib.ok(files[1]:find(name, 1, true), "the unignored file is listed")
end

lib.test("grep in a folder the parent ignores finds what its local .ignore unignores, and nothing else", function()
  local dir, name = vendor()
  local screen = h.nvim(dir)
  screen:exec("Snacks.picker.grep({ cwd = ... })", { dir })
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'grep' }) == 1")
  end, "the grep picker never opened")
  only_unignored(results(screen, "grep", "class"), name)
  screen:close()
end)

lib.test("the cached file picker lists what the local .ignore unignores, and nothing else", function()
  local dir, name = vendor()
  local screen = h.nvim(dir)
  screen:exec("Snacks.picker.files(require('core.file-cache').opts())")
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'files' }) == 1")
  end, "the files picker never opened")
  only_unignored(results(screen, "files", "php"), name)
  screen:close()
end)

lib.test("a plain Snacks.picker.files() does the same (no file cache)", function()
  local dir, name = vendor()
  local screen = h.nvim(dir)
  screen:exec("Snacks.picker.files({ cwd = ... })", { dir })
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'files' }) == 1")
  end, "the files picker never opened")
  only_unignored(results(screen, "files", "php"), name)
  screen:close()
end)
