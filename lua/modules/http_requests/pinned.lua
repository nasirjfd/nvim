-- The requests pinned to the top of the HTTP Requests pane, kept between sessions (per project directory)
-- in stdpath("state")/http-pinned-requests.json. A pin is the request's file (relative to the project) plus
-- its method, URL and name, so it survives edits that move the request to another line.
local M = {}

local file = vim.env.NVIM_CONFIG_TESTS and (vim.fn.tempname() .. "-http-pinned.json")
  or (vim.fn.stdpath("state") .. "/http-pinned-requests.json")

local data ---@type table<string, { file: string, method: string, url: string, name: string }[]>?

--- Use another file (the automated tests give two sessions the same one).
function M.set_file(path)
  file = path
  data = nil
end

local function load()
  if data then
    return data
  end
  data = {}
  local fd = io.open(file, "r")
  if fd then
    local ok, decoded = pcall(vim.json.decode, fd:read("*a"))
    fd:close()
    if ok and type(decoded) == "table" then
      data = decoded
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

local function same(a, b)
  return a.file == b.file and a.method == b.method and a.url == b.url and a.name == b.name
end

local function pin_of(rel, req)
  return { file = rel, method = req.method, url = req.url, name = req.name }
end

--- The pins of `root`, in the order they were pinned.
function M.list(root)
  return load()[root] or {}
end

function M.is_pinned(root, rel, req)
  local want = pin_of(rel, req)
  for _, pin in ipairs(M.list(root)) do
    if same(pin, want) then
      return true
    end
  end
  return false
end

--- Pin the request, or unpin it when it is pinned; returns whether it is pinned now.
function M.toggle(root, rel, req)
  local want = pin_of(rel, req)
  local kept, found = {}, false
  for _, pin in ipairs(M.list(root)) do
    if same(pin, want) then
      found = true
    else
      kept[#kept + 1] = pin
    end
  end
  if not found then
    kept[#kept + 1] = want
  end
  load()[root] = #kept > 0 and kept or nil
  save()
  return not found
end

return M
