-- Database client: nvim-dbee, with project connections from `.nvim.lua` (configure) and a form to
-- edit a result row (e / <CR> on a row of the result pane, see form.lua).
local M = {}

local project = { name = nil, connections = {} }

local function project_source()
  return require("dbee.sources").MemorySource:new(vim.deepcopy(project.connections), project.name)
end

---Connections of the project, called from its `.nvim.lua`:
---  require("modules.database").configure({ name = "supernova", connections = { { name, type, url }, ... } })
---They are listed in dbee next to the connections saved from dbee itself (which survive restarts).
---@param opts { name?: string, connections: { name: string, type: string, url: string }[] }
function M.configure(opts)
  project.name = opts.name or vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
  project.connections = opts.connections or {}
  -- dbee already running (`.nvim.lua` sourced again): add them now.
  local ok, api = pcall(require, "dbee.api")
  if ok and api.core.is_loaded() then
    api.core.add_source(project_source())
    pcall(api.ui.drawer_refresh)
  end
end

function M.connections()
  return vim.deepcopy(project.connections)
end

---1-based number of the result row under the cursor of a dbee result buffer (rows are numbered at the
---start of their line; a wrapped row continues on lines without a number).
---@param buf integer
---@param line integer cursor line
---@return integer|nil
function M.row_at(buf, line)
  for l = line, 1, -1 do
    local text = vim.api.nvim_buf_get_lines(buf, l - 1, l, false)[1] or ""
    local n = text:match("^%s*(%d+)%s")
    if n then
      return tonumber(n)
    end
  end
end

---Edit the row under the cursor of the result pane.
function M.edit_row()
  local backend = require("modules.database.backend")
  local call, conn = backend.current()
  if not call or not conn then
    return vim.notify("No result to edit", vim.log.levels.WARN, { title = "Database" })
  end
  if call.state ~= "archived" and call.state ~= "retrieving" then
    return vim.notify("The query has not finished", vim.log.levels.WARN, { title = "Database" })
  end
  local index = M.row_at(0, vim.api.nvim_win_get_cursor(0)[1])
  if not index then
    return vim.notify("Put the cursor on a row", vim.log.levels.WARN, { title = "Database" })
  end
  local query = call.query
  local win = vim.api.nvim_get_current_win()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  require("modules.database.form").open(conn, call, index, function()
    -- Show the changed row: run the query again and put the cursor back on the same line.
    local api = require("dbee.api")
    local new_call = api.core.connection_execute(conn.id, query)
    api.ui.result_set_call(new_call)
    local listener_done = false
    api.core.register_event_listener("call_state_changed", function(data)
      if listener_done or not data.call or data.call.id ~= new_call.id then
        return
      end
      if data.call.state == "archived" or data.call.state:find("failed") then
        listener_done = true
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(win) then
            local count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
            pcall(vim.api.nvim_win_set_cursor, win, { math.min(line, count), 0 })
          end
        end)
      end
    end)
  end)
end

-- Keys of the result pane (dbee configures the buffer each time it is shown, so on FileType).
local function map_result(buf)
  if not vim.api.nvim_buf_get_name(buf):find("dbee%-result") then
    return
  end
  for _, lhs in ipairs({ "e", "<CR>", "<2-LeftMouse>" }) do
    vim.keymap.set("n", lhs, M.edit_row, { buffer = buf, desc = "Edit this row", nowait = true })
  end
end

---Run the selected SQL (or the paragraph under the cursor) of any buffer on the current connection.
function M.run_selection()
  local text
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    vim.cmd('noautocmd normal! "zy')
    text = vim.fn.getreg("z")
  else
    local start = vim.fn.search("^\\s*$", "bnW") + 1
    local stop = vim.fn.search("^\\s*$", "nW")
    stop = stop == 0 and vim.fn.line("$") or stop - 1
    text = table.concat(vim.api.nvim_buf_get_lines(0, start - 1, stop, false), "\n")
  end
  if vim.trim(text) == "" then
    return
  end
  local ok, err = pcall(require("dbee").execute, text)
  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR, { title = "Database" })
  end
end

function M.setup()
  local sources = require("dbee.sources")
  require("dbee").setup({
    sources = {
      sources.EnvSource:new("DBEE_CONNECTIONS"),
      sources.FileSource:new(vim.fn.stdpath("state") .. "/dbee/persistence.json"),
      project_source(),
    },
  })
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("database_result_keys", { clear = true }),
    pattern = "dbee",
    callback = function(ev)
      map_result(ev.buf)
    end,
  })
end

return M
