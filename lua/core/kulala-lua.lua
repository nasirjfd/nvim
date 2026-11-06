-- Completion for Kulala's Lua scripts (`> {% -- lua … %}` blocks in .http files), as a blink.cmp
-- source. Kulala's own language server only offers JavaScript-style snippets there (`response.json()`),
-- not the Lua API (`response.json.token`, `client.global.Name = …`). Members come from the API
-- documented in kulala.nvim's docs/scripts/lua-scripts.md, plus what the document and the last
-- responses know: names set on client.global, request names under client.responses, and the keys of
-- the last JSON response under response.json.
local M = {}

local Kind = { Function = 3, Field = 5, Variable = 6, Module = 9, Property = 10 }

local function fn(doc, snippet)
  return { kind = Kind.Function, doc = doc, snippet = snippet }
end
local function field(doc)
  return { kind = Kind.Field, doc = doc }
end

-- Static API tree: node = { kind, doc, snippet?, children? }
local API = {
  client = {
    kind = Kind.Module,
    doc = "The client object",
    children = {
      global = { kind = Kind.Module, doc = "Global variables kept between requests", children = "client.global" },
      responses = { kind = Kind.Module, doc = "Responses of previous requests, by request name", children = "client.responses" },
      clear_all = fn("Clear all global variables", "clear_all()"),
      log = fn("Log a message", "log(${1:message})"),
      test = fn("Define a test suite", "test(${1:name}, function()\n\t$0\nend)"),
      assert = fn("Alias for assert", "assert(${1:value}, ${2:message})"),
    },
  },
  request = {
    kind = Kind.Module,
    doc = "The request object",
    children = {
      metadata = field("{ name, value }[] — metadata of the request"),
      environment = field("table — the environment and document variables"),
      variables = field("table — request variables (alias for environment)"),
      method = field("string — the HTTP method"),
      url = field("string — the URL with variables replaced"),
      url_raw = field("string — the URL as in the document"),
      request_target = field("string|nil"),
      http_version = field("string"),
      headers = field("table — headers with variables replaced"),
      headers_raw = field("table — headers as in the document"),
      headers_display = field("table — headers, sanitized"),
      cookie = field("string"),
      body = field("string|nil — the body with variables replaced"),
      body_raw = field("string|nil — the raw body"),
      body_computed = field("string|nil — the body as sent by curl"),
      body_display = field("string|nil — the body, sanitized"),
      skip = fn("Skip the request (pre-request scripts)", "skip()"),
      replay = fn("Replay the request (post-request scripts)", "replay()"),
      iteration = fn("Current count of request replays", "iteration()"),
    },
  },
  response = {
    kind = Kind.Module,
    doc = "The response object",
    children = {
      id = field("string"),
      name = field("string — name of the request"),
      url = field("string — request url"),
      method = field("string — request method"),
      request = field("{ headers_tbl, body }"),
      status = field("boolean — status of the request"),
      code = field("number — command exit code"),
      response_code = field("number — HTTP response code"),
      duration = field("number"),
      time = field("number"),
      body = field("string — body of the response"),
      body_raw = field("string — body, unaltered"),
      json = { kind = Kind.Field, doc = "table — the JSON response", children = "response.json" },
      filter = field("string|nil — jq filter if applied"),
      headers = field("string — headers of the response"),
      headers_tbl = field("table — parsed headers"),
      cookies = field("table — received cookies"),
      errors = field("string"),
      stats = field("table|string"),
      assert_output = field("table"),
      assert_status = field("boolean"),
      file = field("string — path of the file of the request"),
      buf = field("number"),
      buf_name = field("string"),
      line = field("number"),
    },
  },
  assert = {
    kind = Kind.Module,
    doc = "Assertion functions",
    children = {
      test = fn("Define a test suite", "test(${1:name}, function()\n\t$0\nend)"),
      is_true = fn("Check that a value is true", "is_true(${1:value}, ${2:message})"),
      is_false = fn("Check that a value is false", "is_false(${1:value}, ${2:message})"),
      same = fn("Check that a value is the expected one", "same(${1:value}, ${2:expected}, ${3:message})"),
      has_string = fn("Check that a value has the string", "has_string(${1:value}, ${2:expected}, ${3:message})"),
      response_has = fn("Check a key:value of the response", "response_has(${1:key}, ${2:expected}, ${3:message})"),
      headers_has = fn("Check a key:value of the headers", "headers_has(${1:key}, ${2:expected}, ${3:message})"),
      body_has = fn("Check that the body has the string", "body_has(${1:expected}, ${2:message})"),
      json_has = fn("Check a key:value of the JSON", "json_has(${1:key}, ${2:expected}, ${3:message})"),
    },
  },
}

--- Is line `lnum` (1-based) of the buffer inside a `{% … %}` block written in Lua?
function M.in_lua_block(bufnr, lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, lnum, false)
  local start
  for index = #lines, 1, -1 do
    local text = lines[index]
    if index < #lines and text:find("%%}") then
      return false -- a block that ended above
    end
    if text:find("{%%") then
      start = index
      break
    end
  end
  if not start then
    return false
  end
  local all = vim.api.nvim_buf_get_lines(bufnr, start - 1, math.min(start + 3, vim.api.nvim_buf_line_count(bufnr)), false)
  for _, text in ipairs(all) do
    if text:find("^%s*%-%-%s*lua%s*$") or text:find("{%%%s*%-%-%s*lua") then
      return true
    end
  end
  return false
end

local function names_in_buffer(bufnr, pattern)
  local seen, names = {}, {}
  for _, text in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    for name in text:gmatch(pattern) do
      if not seen[name] then
        seen[name] = true
        names[#names + 1] = name
      end
    end
  end
  return names
end

local function json_keys(bufnr, lnum, path)
  local ok, db = pcall(require, "kulala.db")
  if not ok then
    return {}
  end
  local wanted
  for index = lnum, 1, -1 do
    local name = vim.api.nvim_buf_get_lines(bufnr, index - 1, index, false)[1]:match("^%s*[#/]+%s*@name%s+(%S+)")
    if name then
      wanted = name
      break
    end
  end
  local responses = (pcall(function() return db.global_update().responses end) and db.global_update().responses) or {}
  local chosen
  for index = #responses, 1, -1 do
    local r = responses[index]
    if r.json or (r.body and r.body:match("^%s*[{%[]")) then
      if not wanted or r.name == wanted then
        chosen = r
        break
      end
      chosen = chosen or r
    end
  end
  if not chosen then
    return {}
  end
  local data = chosen.json
  if type(data) ~= "table" then
    local decoded, value = pcall(vim.json.decode, chosen.body or "")
    data = decoded and value or nil
  end
  for segment in vim.gsplit(path, ".", { plain = true }) do
    if segment ~= "" then
      data = type(data) == "table" and data[segment] or nil
    end
  end
  local keys = {}
  if type(data) == "table" then
    for key, value in pairs(data) do
      if type(key) == "string" then
        keys[#keys + 1] = { name = key, kind = type(value) == "table" and Kind.Module or Kind.Field, doc = type(value) }
      end
    end
  end
  return keys
end

--- Members of the object at `path` (e.g. "client.global").
local function members(bufnr, lnum, path)
  local parts = vim.split(path, ".", { plain = true })
  local node = { children = API }
  for _, part in ipairs(parts) do
    if type(node.children) ~= "table" then
      node = nil
      break
    end
    node = node.children[part]
    if not node then
      break
    end
  end
  local items = {}
  if node and type(node.children) == "table" then
    for name, child in pairs(node.children) do
      items[#items + 1] = { name = name, kind = child.kind, doc = child.doc, snippet = child.snippet }
    end
  elseif path == "client.global" then
    for _, name in ipairs(names_in_buffer(bufnr, "client%.global%.([%a_][%w_]*)%s*=")) do
      items[#items + 1] = { name = name, kind = Kind.Variable, doc = "global variable set in this file" }
    end
    for _, name in ipairs(names_in_buffer(bufnr, "client%.global%.set%(%s*[\"']([%w_]+)[\"']")) do
      items[#items + 1] = { name = name, kind = Kind.Variable, doc = "global variable set in this file" }
    end
  elseif path == "client.responses" then
    for _, name in ipairs(names_in_buffer(bufnr, "[#/]+%s*@name%s+([%w_]+)")) do
      items[#items + 1] = { name = name, kind = Kind.Field, doc = "response of the request " .. name }
    end
  elseif path == "response.json" or path:find("^response%.json%.") then
    items = json_keys(bufnr, lnum, path:gsub("^response%.json%.?", ""))
  end
  return items
end

--- Variables scripts define: `client.global.Name = …` / `client.global.set("Name", …)` anywhere in the
--- document, plus whatever is stored by requests already run (Kulala keeps them in a JSON file).
local function script_variables(bufnr)
  local found, seen = {}, {}
  local function add(name, doc)
    if not seen[name] then
      seen[name] = true
      found[#found + 1] = { name = name, doc = doc }
    elseif doc and not seen[name] == true then
      seen[name] = true
    end
  end
  local stored = {}
  pcall(function()
    local path = require("kulala.utils.fs").get_global_scripts_variables_file_path()
    stored = require("kulala.utils.fs").read_json(path) or {}
  end)
  for _, name in ipairs(names_in_buffer(bufnr, "client%.global%.([%a_][%w_]*)%s*=[^=]")) do
    local value = stored[name]
    add(name, "set by a script" .. (value ~= nil and (" — now: " .. vim.inspect(value)) or ""))
  end
  for _, name in ipairs(names_in_buffer(bufnr, "client%.global%.set%(%s*[\"']([%w_%.%-]+)[\"']")) do
    local value = stored[name]
    add(name, "set by a script" .. (value ~= nil and (" — now: " .. vim.inspect(value)) or ""))
  end
  for name, value in pairs(stored) do
    if type(name) == "string" and name:find("^%a") then
      add(name, "stored by an earlier request — now: " .. vim.inspect(value))
    end
  end
  return found
end

-- blink.cmp source
local Source = {}
Source.__index = Source

function Source.new()
  return setmetatable({}, Source)
end

function Source:enabled()
  return vim.bo.filetype == "http"
end

function Source:get_trigger_characters()
  return { "." }
end

function Source:get_completions(ctx, callback)
  local bufnr = ctx.bufnr
  local lnum = ctx.cursor[1]
  local before = ctx.line:sub(1, ctx.cursor[2])
  if not M.in_lua_block(bufnr, lnum) then
    -- {{name}} in a URL, header or body: the variables scripts define (Kulala's own list has the
    -- document, environment and request names, not these)
    local items = {}
    if before:find("{{%s*[%w_%.%-]*$") then
      for _, variable in ipairs(script_variables(bufnr)) do
        items[#items + 1] = {
          label = variable.name,
          kind = Kind.Variable,
          labelDetails = { description = "script" },
          documentation = { kind = "plaintext", value = variable.doc },
        }
      end
    end
    return callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
  end
  local path = before:match("([%a_][%w_%.]*)%.[%w_]*$")
  local items = {}
  if path then
    for _, member in ipairs(members(bufnr, lnum, path)) do
      items[#items + 1] = {
        label = member.name,
        kind = member.kind,
        documentation = member.doc and { kind = "plaintext", value = member.doc } or nil,
        insertText = member.snippet or member.name,
        insertTextFormat = member.snippet and 2 or 1,
      }
    end
  else
    for name, node in pairs(API) do
      items[#items + 1] = { label = name, kind = node.kind, documentation = { kind = "plaintext", value = node.doc } }
    end
  end
  callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

M.Source = Source
M.new = Source.new

return M
