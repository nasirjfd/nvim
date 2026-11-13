-- Hidden folders, files and requests, kept per project in the existing http-hidden-folders.json.
local M = {}

local file = vim.env.NVIM_CONFIG_TESTS and (vim.fn.tempname() .. "-http-hidden.json")
  or (vim.fn.stdpath("state") .. "/http-hidden-folders.json")

local data ---@type table?

--- Use another file (the automated tests give two sessions the same one).
function M.set_file(path)
  file = path
  data = nil
end

local function load()
  if data then
    return data
  end
  data = { dirs = {}, files = {}, requests = {}, show = false }
  local fd = io.open(file, "r")
  if fd then
    local ok, decoded = pcall(vim.json.decode, fd:read("*a"))
    fd:close()
    if ok and type(decoded) == "table" then
      data.dirs = type(decoded.dirs) == "table" and decoded.dirs or {}
      data.files = type(decoded.files) == "table" and decoded.files or {}
      data.requests = type(decoded.requests) == "table" and decoded.requests or {}
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

--- The hidden entries of `root` as a set; old callers default to folders.
function M.set(root, kind)
  local out = {}
  for _, path in ipairs(load()[kind or "dirs"][root] or {}) do
    out[path] = true
  end
  return out
end

--- Hide/unhide an entry, returning whether it is hidden now.
function M.toggle(root, path, kind)
  local bucket = load()[kind or "dirs"]
  local list = bucket[root] or {}
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
  bucket[root] = #kept > 0 and kept or nil
  save()
  return not found
end

-- Like pins, request identity survives edits that shift its line number.
function M.request_key(rel, req)
  return vim.json.encode({ rel, req.method, req.url, req.name })
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
