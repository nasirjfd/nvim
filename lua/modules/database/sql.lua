-- Pure SQL helpers of the row edit form: which table a query reads, how a value is written in the form,
-- and the UPDATE statement of an edited row. No dbee, no editor state: tested directly.
local M = {}

-- Databases the form can write to. Anything else gets a clear "not supported" message.
M.dialects = { mysql = true, mariadb = true, sqlite = true }

local function dialect_of(kind)
  return (kind == "mariadb") and "mysql" or kind
end

-- Blank out string literals and quoted identifiers so keywords inside them ("... WHERE note = 'join'")
-- are not mistaken for SQL. Same length, so positions still match the original text.
local function mask_quotes(text)
  return (text:gsub("'[^']*'", function(s)
    return "'" .. string.rep(" ", #s - 2) .. "'"
  end))
end

-- Comments become spaces (same length), found outside string literals.
local function strip_comments(query)
  local masked = mask_quotes(query)
  for _, pattern in ipairs({ "/%*.-%*/", "%-%-[^\n]*", "#[^\n]*" }) do
    local init = 1
    while true do
      local s, e = masked:find(pattern, init)
      if not s then
        break
      end
      local blank = string.rep(" ", e - s + 1)
      masked = masked:sub(1, s - 1) .. blank .. masked:sub(e + 1)
      query = query:sub(1, s - 1) .. blank .. query:sub(e + 1)
      init = e + 1
    end
  end
  return query
end

-- One identifier part at `pos`: `name`, "name", [name] or bare name. Returns the name and the
-- position after it.
local function read_ident(text, pos)
  local open = text:sub(pos, pos)
  local close = ({ ["`"] = "`", ['"'] = '"', ["["] = "]" })[open]
  if close then
    local stop = text:find(close, pos + 1, true)
    if not stop then
      return nil
    end
    return text:sub(pos + 1, stop - 1), stop + 1
  end
  local name = text:match("^[%w_$]+", pos)
  if not name then
    return nil
  end
  return name, pos + #name
end

local FOLLOWING = {
  where = true,
  order = true,
  limit = true,
  offset = true,
  ["for"] = true,
  lock = true,
  window = true,
}

---The table a SELECT reads, when it reads exactly one table (no join, union, grouping or subquery).
---@param query string
---@return { schema: string|nil, table: string }|nil
---@return string|nil reason why the rows of this query cannot be edited
function M.source_table(query)
  local text = strip_comments(query or ""):gsub(";%s*$", "")
  text = vim.trim(text)
  local masked = mask_quotes(text):lower()
  if not masked:match("^select%s") then
    return nil, "only the rows of a SELECT can be edited"
  end
  local _, selects = masked:gsub("%f[%w_]select%f[^%w_]", "")
  if selects > 1 then
    return nil, "the query has a subquery or a UNION: edit the rows of a query on one table"
  end
  for word, label in pairs({ join = "JOIN", union = "UNION", group = "GROUP BY", having = "HAVING" }) do
    if masked:find("%f[%w_]" .. word .. "%f[^%w_]") then
      return nil, ("the query uses %s: edit the rows of a query on one table"):format(label)
    end
  end
  local from = masked:find("%f[%w_]from%f[^%w_]")
  if not from then
    return nil, "the query reads no table"
  end
  local pos = text:find("%S", from + 4)
  if not pos then
    return nil, "the query reads no table"
  end
  local parts = {}
  while true do
    local name, after = read_ident(text, pos)
    if not name then
      return nil, "could not read the table name of the query"
    end
    parts[#parts + 1] = name
    if text:sub(after, after) ~= "." then
      pos = after
      break
    end
    pos = after + 1
  end
  if #parts > 2 then
    return nil, "could not read the table name of the query"
  end
  -- After the table: nothing, an alias, or a clause. A comma means a second table.
  local rest = vim.trim(mask_quotes(text:sub(pos)):lower())
  rest = rest:gsub("^as%s+", "")
  local word = rest:match('^[%w_$`"]+')
  if word and not FOLLOWING[word] then
    rest = vim.trim(rest:sub(#word + 1))
    word = rest:match("^[%w_]+")
  end
  if rest ~= "" and not FOLLOWING[word or ""] then
    return nil, "the query reads more than one table: edit the rows of a query on one table"
  end
  return { schema = parts[2] and parts[1] or nil, table = parts[2] or parts[1] }
end

-- How a value is shown on its line of the form, and read back. One line per column, so a newline is
-- written \n and a backslash \\. NULL is the word NULL; the text "NULL" is written \NULL.
---@param value string|nil nil is SQL NULL
---@return string
function M.encode(value)
  if value == nil then
    return "NULL"
  end
  if value == "NULL" then
    return "\\NULL"
  end
  return (value:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "\\r"))
end

---@param line string
---@return string|nil
function M.decode(line)
  if line == "NULL" then
    return nil
  end
  if line == "\\NULL" then
    return "NULL"
  end
  return (
    line:gsub("\\(.)", function(c)
      if c == "n" then
        return "\n"
      elseif c == "r" then
        return "\r"
      elseif c == "\\" then
        return "\\"
      end
      return "\\" .. c
    end)
  )
end

---@param kind string connection type
---@param name string
function M.quote_ident(kind, name)
  if dialect_of(kind) == "mysql" then
    return "`" .. name:gsub("`", "``") .. "`"
  end
  return '"' .. name:gsub('"', '""') .. '"'
end

---A value as an SQL literal. Text is quoted with '' doubled; in MySQL a value with a backslash or a NUL
---byte is written as hex, which means the same with or without NO_BACKSLASH_ESCAPES.
---@param kind string connection type
---@param value string|nil
function M.literal(kind, value)
  if value == nil then
    return "NULL"
  end
  if dialect_of(kind) == "mysql" and value:find("[\\%z]") then
    return "_utf8mb4 X'"
      .. value:gsub(".", function(c)
        return ("%02X"):format(c:byte())
      end)
      .. "'"
  end
  return "'" .. value:gsub("'", "''") .. "'"
end

---@param kind string connection type
---@param target { schema: string|nil, table: string }
function M.table_name(kind, target)
  local name = M.quote_ident(kind, target.table)
  if target.schema then
    name = M.quote_ident(kind, target.schema) .. "." .. name
  end
  return name
end

---The UPDATE of one row: the changed columns, found by the primary key.
---@param kind string connection type
---@param target { schema: string|nil, table: string }
---@param key { name: string, value: string }[] primary key columns and their values
---@param changes { name: string, value: string|nil }[]
---@return string
function M.update(kind, target, key, changes)
  local set, where = {}, {}
  for i, c in ipairs(changes) do
    set[#set + 1] = (i == 1 and "SET " or "    ")
      .. M.quote_ident(kind, c.name)
      .. " = "
      .. M.literal(kind, c.value)
  end
  for _, k in ipairs(key) do
    where[#where + 1] = M.quote_ident(kind, k.name) .. " = " .. M.literal(kind, k.value)
  end
  local lines = { "UPDATE " .. M.table_name(kind, target), table.concat(set, ",\n") }
  lines[#lines + 1] = "WHERE " .. table.concat(where, " AND ")
  if dialect_of(kind) == "mysql" then
    lines[#lines + 1] = "LIMIT 1"
  end
  return table.concat(lines, "\n")
end

---The query that describes the columns of a table: name, type, nullable, part of the primary key,
---generated. Each dialect returns the same field names.
---@param kind string connection type
---@param target { schema: string|nil, table: string }
---@return string
function M.columns_query(kind, target)
  if dialect_of(kind) == "mysql" then
    local schema = target.schema and M.literal(kind, target.schema) or "DATABASE()"
    return table.concat({
      "SELECT COLUMN_NAME AS name, COLUMN_TYPE AS type, DATA_TYPE AS base_type,",
      "IS_NULLABLE AS nullable, COLUMN_KEY AS col_key, EXTRA AS extra",
      "FROM information_schema.COLUMNS",
      ("WHERE TABLE_SCHEMA = %s AND TABLE_NAME = %s"):format(schema, M.literal(kind, target.table)),
      "ORDER BY ORDINAL_POSITION",
    }, " ")
  end
  local args = M.literal(kind, target.table)
  if target.schema then
    args = args .. ", " .. M.literal(kind, target.schema)
  end
  return (
    "SELECT name, type, type AS base_type, "
    .. "CASE WHEN \"notnull\" = 1 THEN 'NO' ELSE 'YES' END AS nullable, pk, "
    .. "CASE WHEN hidden IN (2, 3) THEN 'generated' ELSE '' END AS extra "
    .. "FROM pragma_table_xinfo(%s) ORDER BY cid"
  ):format(args)
end

local READ_ONLY_TYPES = {
  blob = true,
  tinyblob = true,
  mediumblob = true,
  longblob = true,
  binary = true,
  varbinary = true,
  bit = true,
  geometry = true,
  point = true,
  linestring = true,
  polygon = true,
  multipoint = true,
  multilinestring = true,
  multipolygon = true,
  geometrycollection = true,
}

---Columns from the rows of columns_query: { name, type, nullable, key (position in the primary key or
---nil), read_only (a reason or nil) }.
---@param kind string
---@param rows table[] decoded JSON rows
function M.columns(kind, rows)
  local list = {}
  local mysql_key = 0
  for _, r in ipairs(rows) do
    local function field(name)
      local v = r[name]
      if v == nil or v == vim.NIL then
        return ""
      end
      return tostring(v)
    end
    local col = {
      name = field("name"),
      type = field("type"),
      nullable = field("nullable"):upper() == "YES",
    }
    if dialect_of(kind) == "mysql" then
      if field("col_key") == "PRI" then
        mysql_key = mysql_key + 1
        col.key = mysql_key
      end
    else
      local pk = tonumber(field("pk")) or 0
      col.key = pk > 0 and pk or nil
    end
    local extra = field("extra"):lower()
    if READ_ONLY_TYPES[field("base_type"):lower()] then
      col.read_only = "binary"
    elseif extra:find("generated") or extra:find("virtual") or extra:find("stored") then
      col.read_only = "generated"
    elseif col.key then
      col.read_only = "primary key"
    end
    list[#list + 1] = col
  end
  return list
end

return M
