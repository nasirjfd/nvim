-- dbee connections from a Supernova `config/<env>/mysql.yml`. The file can hold several `mysql:` blocks,
-- the inactive ones commented out; each block becomes one connection (its `default` database). The
-- password is read from the file when Neovim starts, so it is never copied into this repository.
local M = {}

---@param text string
---@return { host: string, port: string, dbname: string, user: string, pass: string }[]
function M.parse(text)
  local blocks, block, section = {}, nil, nil
  for raw in (text .. "\n"):gmatch("(.-)\r?\n") do
    local line = raw:gsub("^%s*#%s?", "")
    local indent, key, value = line:match("^(%s*)([%w_]+):%s*(.-)%s*$")
    if key and #indent == 0 then
      if key == "mysql" then
        block = {}
        blocks[#blocks + 1] = block
      else
        block = nil
      end
      section = nil
    elseif key and block then
      if value == "" then
        section = key
      elseif section == "default" then
        value = value:gsub("^['\"](.*)['\"]$", "%1")
        block[key] = value
      end
    end
  end
  local list = {}
  for _, b in ipairs(blocks) do
    local uri = b.uri or ""
    local entry = {
      host = uri:match("host=([^;]+)"),
      port = uri:match("port=([^;]+)") or "3306",
      dbname = uri:match("dbname=([^;]+)"),
      user = b.user,
      pass = b.pass or "",
    }
    if entry.host and entry.user then
      list[#list + 1] = entry
    end
  end
  return list
end

---@param path string mysql.yml
---@param envs table<string, { name: string, host?: string, port?: string|integer }> by the host in the file:
---  the connection name, and where to reach it from this machine (e.g. a container's published port)
---@return { name: string, type: string, url: string }[]
function M.connections(path, envs)
  local file = io.open(vim.fn.expand(path), "r")
  if not file then
    vim.notify("Database: " .. path .. " not found", vim.log.levels.WARN)
    return {}
  end
  local text = file:read("*a")
  file:close()
  local list = {}
  for _, e in ipairs(M.parse(text)) do
    local env = envs[e.host] or {}
    list[#list + 1] = {
      name = env.name or ("mysql_" .. e.host),
      type = "mysql",
      url = ("%s:%s@tcp(%s:%s)/%s"):format(
        e.user,
        e.pass,
        env.host or e.host,
        tostring(env.port or e.port),
        e.dbname or ""
      ),
    }
  end
  table.sort(list, function(a, b)
    return a.name < b.name
  end)
  return list
end

return M
