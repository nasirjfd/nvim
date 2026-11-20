-- The dbee side of the row edit form: run a statement without touching the result pane, and read rows
-- of a finished call as JSON. Kept apart so the form can be driven by a fake in tests.
local M = {}

local pending = {} -- call id -> callback(err, call)
local listening = false

local DONE = { archived = true }
local FAILED =
  { executing_failed = true, retrieving_failed = true, archive_failed = true, canceled = true }

local function api()
  return require("dbee.api")
end

local function finish(id, err, call)
  local cb = pending[id]
  if cb then
    pending[id] = nil
    cb(err, call)
  end
end

local function listen()
  if listening then
    return
  end
  listening = true
  api().core.register_event_listener("call_state_changed", function(data)
    local call = data and data.call
    if not call or not pending[call.id] then
      return
    end
    if DONE[call.state] then
      finish(call.id, nil, call)
    elseif FAILED[call.state] then
      finish(call.id, call.error ~= "" and call.error or call.state, call)
    end
  end)
end

---Run a statement on a connection; cb(err, call) once it finished. The result pane keeps showing what
---it showed (the statement still appears in dbee's call log).
---@param conn_id string
---@param query string
---@param cb fun(err: string|nil, call: CallDetails|nil)
---@param timeout_ms? integer
function M.run(conn_id, query, cb, timeout_ms)
  listen()
  local ok, call = pcall(api().core.connection_execute, conn_id, query)
  if not ok or not call then
    return cb(tostring(call or "could not run the statement"))
  end
  pending[call.id] = vim.schedule_wrap(cb)
  vim.defer_fn(function()
    finish(call.id, ("no answer from the database after %d s"):format((timeout_ms or 30000) / 1000))
  end, timeout_ms or 30000)
end

---Rows [from, to) (0-based, `to` exclusive) of a finished call, decoded; NULL is vim.NIL.
---@param call_id string
---@param from? integer
---@param to? integer
---@return table[]|nil rows
---@return string|nil err
function M.rows(call_id, from, to)
  local buf = vim.api.nvim_create_buf(false, true)
  local ok, err = pcall(api().core.call_store_result, call_id, "json", "buffer", {
    from = from or 0,
    to = to or -1,
    extra_arg = buf,
  })
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  vim.api.nvim_buf_delete(buf, { force = true })
  if not ok then
    return nil, tostring(err)
  end
  if text == "" or text == "null" then
    return {}
  end
  local decoded_ok, rows = pcall(vim.json.decode, text)
  if not decoded_ok or type(rows) ~= "table" then
    return nil, "could not read the rows"
  end
  return rows
end

---The call shown in the result pane and its connection.
---@return CallDetails|nil call
---@return ConnectionParams|nil conn
function M.current()
  local a = api()
  local ok, call = pcall(a.ui.result_get_call)
  if not ok or not call then
    return nil
  end
  -- The call belongs to the connection whose call list holds it (usually the current one).
  local current = a.core.get_current_connection()
  local function owns(conn)
    local ok_calls, calls = pcall(a.core.connection_get_calls, conn.id)
    for _, c in ipairs(ok_calls and calls or {}) do
      if c.id == call.id then
        return true
      end
    end
  end
  if current and owns(current) then
    return call, current
  end
  for _, source in ipairs(a.core.get_sources()) do
    for _, conn in ipairs(a.core.source_get_connections(source:name()) or {}) do
      if owns(conn) then
        return call, conn
      end
    end
  end
  return call, current
end

---Run the query again and show it in the result pane (after a row was changed).
---@param conn_id string
---@param query string
function M.rerun(conn_id, query)
  local a = api()
  a.ui.result_set_call(a.core.connection_execute(conn_id, query))
end

return M
