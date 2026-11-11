-- The folders hidden from the HTTP Requests pane, kept between sessions (per project directory) in
-- stdpath("state")/http-hidden-folders.json, and whether the pane shows them (dimmed) or not.
local M = {}

local file = vim.env.NVIM_CONFIG_TESTS and (vim.fn.tempname() .. "-http-hidden.json")
  or (vim.fn.stdpath("state") .. "/http-hidden-folders.json")

local data ---@type { dirs: table<string, string[]>, show: boolean }?

--- Use another file (the automated tests give two sessions the same one).
function M.set_file(path)
  file = path
  data = nil
end

local function load()
  if data then
    return data
  end
  data = { dirs = {}, show = false }
  local fd = io.open(file, "r")
  if fd then
    local ok, decoded = pcall(vim.json.decode, fd:read("*a"))
    fd:close()
    if ok and type(decoded) == "table" then
      data.dirs = type(decoded.dirs) == "table" and decoded.dirs or {}
      data.show = decoded.show == true
    end
  end
  return data
end

local function save()
  vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
  local tmp = file .. ".tmp"
  local fd = io.open(tmp, "w")
  if fd then
    fd:write(vim.json.encode(data))
    fd:close()
    os.rename(tmp, file)
  end
end

--- The hidden folders of `root` as a set { ["rel/path"] = true }.
function M.set(root)
  local out = {}
  for _, path in ipairs(load().dirs[root] or {}) do
    out[path] = true
  end
  return out
end

--- Hide the folder `path` (relative to `root`), or show it again when it is hidden; returns whether it is hidden now.
function M.toggle(root, path)
  local list = load().dirs[root] or {}
  local kept, found = {}, false
  for _, existing in ipairs(list) do
    if existing == path then
      found = true
    else
      kept[#kept + 1] = existing
    end
  end
  if not found then
    kept[#kept + 1] = path
  end
  table.sort(kept)
  data.dirs[root] = #kept > 0 and kept or nil
  save()
  return not found
end

function M.showing()
  return load().show
end

function M.toggle_show()
  load().show = not data.show
  save()
  return data.show
end

return M
