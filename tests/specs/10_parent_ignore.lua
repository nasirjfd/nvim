-- A folder the parent repo ignores (supernova's vendor/ with `vendor/*` and `vendor/digiexpress/*`):
-- the parent's .gitignore must not hide files from the file and grep pickers opened inside it.
local lib = require("lib")
local h = require("support")

local function vendor()
  local root = h.tmpdir()
  h.git(root, "init", "-q", "-b", "main")
  h.write(root .. "/.gitignore", { "vendor/*", "!vendor/pkg/", "vendor/pkg/*", "!vendor/pkg/keep/" })
  local name = "RequestRouteCapacitiesForMassDescriptionsCommand"
  h.write(root .. "/vendor/pkg/src/" .. name .. ".php", { "<?php", "final class " .. name .. " {}" })
  h.write(root .. "/vendor/pkg/keep/Other.php", { "<?php", "class Other {}" })
  return root .. "/vendor", name
end

lib.test("grep inside a folder ignored by its parent repo finds files the parent's .gitignore hides", function()
  local dir, name = vendor()
  local screen = h.nvim(dir)
  screen:exec("Snacks.picker.grep({ cwd = ... })", { dir })
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'grep' }) == 1")
  end, "the grep picker never opened")
  screen:exec("local p = Snacks.picker.get({ source = 'grep' })[1]; p.input:set(..., ...); p:find()", { name })
  h.wait(screen, function()
    return screen:exec("local p = Snacks.picker.get({ source = 'grep' })[1]; return p and p:count() or 0") > 0
  end, "grep did not find " .. name)
  screen:close()
end)

lib.test("the file picker inside a folder ignored by its parent repo finds files the parent's .gitignore hides", function()
  local dir, name = vendor()
  local screen = h.nvim(dir)
  screen:exec("Snacks.picker.files(require('core.file-cache').opts())")
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'files' }) == 1")
  end, "the files picker never opened")
  screen:exec("local p = Snacks.picker.get({ source = 'files' })[1]; p.input:set(..., ...); p:find()", { name })
  h.wait(screen, function()
    return screen:exec("local p = Snacks.picker.get({ source = 'files' })[1]; return p and p:count() or 0") > 0
  end, "the files picker did not find " .. name)
  screen:close()
end)

lib.test("a plain Snacks.picker.files() in such a folder finds them too (no file cache)", function()
  local dir, name = vendor()
  local screen = h.nvim(dir)
  screen:exec("Snacks.picker.files({ cwd = ... })", { dir })
  h.wait(screen, function()
    return screen:exec("return #Snacks.picker.get({ source = 'files' }) == 1")
  end, "the files picker never opened")
  screen:exec("local p = Snacks.picker.get({ source = 'files' })[1]; p.input:set(..., ...); p:find()", { name })
  h.wait(screen, function()
    return screen:exec("local p = Snacks.picker.get({ source = 'files' })[1]; return p and p:count() or 0") > 0
  end, "the plain files picker did not find " .. name)
  screen:close()
end)
