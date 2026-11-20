-- Edit one result row of dbee in a form: a float with one line per column (the column name is a label
-- in front of the line, the line itself is the value), edited with normal Vim motions. Saving shows the
-- UPDATE it will run; confirming runs it by the primary key and reloads the result.
local sql = require("modules.database.sql")

local M = {}

M.backend = require("modules.database.backend")

local ns = vim.api.nvim_create_namespace("database_row_form")
local ns_state = vim.api.nvim_create_namespace("database_row_form_state")

local HELP = {
  "Edit row",
  "",
  "  Each line is the value of the column in front of it; edit it with any Vim motion.",
  "  NULL        the value NULL (write \\NULL for the text NULL)",
  "  \\n          a newline inside the value (\\\\ for a backslash)",
  "",
  "  <C-s>  :w  <CR>   review and apply the change",
  "  <C-n>             set the value under the cursor to NULL",
  "  gr                put back the original value of the line",
  "  u                 undo",
  "  q  <Esc>          close (twice when something changed)",
}

local function set_highlights()
  local function link(name, target)
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
  link("DatabaseFormLabel", "Identifier")
  link("DatabaseFormKey", "Special")
  link("DatabaseFormReadOnly", "Comment")
  link("DatabaseFormType", "Comment")
  link("DatabaseFormNull", "Comment")
  link("DatabaseFormChanged", "DiffChange")
  link("DatabaseFormChangedSign", "DiagnosticWarn")
  link("DatabaseFormError", "DiagnosticError")
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Database" })
end

local function as_text(v)
  if v == nil or v == vim.NIL then
    return nil
  end
  if type(v) == "table" then
    return vim.json.encode(v)
  end
  return tostring(v)
end

---The fields of the form: table columns present in the row (table order), then the other values of the
---row (expressions, aliases) as read only.
local function build_fields(columns, row, table_name)
  local fields, seen = {}, {}
  for _, col in ipairs(columns) do
    if row[col.name] ~= nil then
      seen[col.name] = true
      fields[#fields + 1] = {
        name = col.name,
        type = col.type,
        nullable = col.nullable,
        key = col.key,
        read_only = col.read_only,
        original = as_text(row[col.name]),
      }
    end
  end
  local extra = {}
  for name in pairs(row) do
    if not seen[name] then
      extra[#extra + 1] = name
    end
  end
  table.sort(extra)
  for _, name in ipairs(extra) do
    fields[#fields + 1] = {
      name = name,
      type = "",
      read_only = "not a column of " .. table_name,
      original = as_text(row[name]),
    }
  end
  return fields
end

---@class DatabaseForm
---@field buf integer
---@field win integer
---@field fields table[]
---@field marks integer[]
local Form = {}
Form.__index = Form

function Form:valid()
  return self.win and vim.api.nvim_win_is_valid(self.win) and vim.api.nvim_buf_is_valid(self.buf)
end

---The value of each field from its line, or an error when lines were added or removed.
function Form:values()
  local lines = vim.api.nvim_buf_get_lines(self.buf, 0, -1, false)
  if #lines ~= #self.fields then
    return nil, "a line was added or removed: press u to undo it"
  end
  local seen = {}
  for i, id in ipairs(self.marks) do
    local pos = vim.api.nvim_buf_get_extmark_by_id(self.buf, ns, id, {})
    if not pos[1] or pos[1] ~= i - 1 or seen[pos[1]] then
      return nil, "a line was added or removed: press u to undo it"
    end
    seen[pos[1]] = true
  end
  local values = {}
  for i, line in ipairs(lines) do
    values[i] = sql.decode(line)
  end
  return values
end

---Changed fields, and the read-only ones that were edited.
function Form:diff()
  local values, err = self:values()
  if not values then
    return nil, err
  end
  local changes, blocked = {}, {}
  for i, f in ipairs(self.fields) do
    if values[i] ~= f.original then
      if f.read_only then
        blocked[#blocked + 1] = ("%s (%s)"):format(f.name, f.read_only)
      else
        changes[#changes + 1] = { name = f.name, value = values[i], index = i }
      end
    end
  end
  if #blocked > 0 then
    return nil,
      "these values cannot be changed: " .. table.concat(blocked, ", ") .. " (press gr on them)"
  end
  return changes
end

-- Mark changed lines and NULL values while typing.
function Form:refresh()
  if not self:valid() then
    return
  end
  vim.api.nvim_buf_clear_namespace(self.buf, ns_state, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(self.buf, 0, -1, false)
  for i, line in ipairs(lines) do
    local f = self.fields[i]
    if line == "NULL" then
      vim.api.nvim_buf_set_extmark(self.buf, ns_state, i - 1, 0, {
        end_col = #line,
        hl_group = "DatabaseFormNull",
      })
    end
    if f and sql.decode(line) ~= f.original then
      vim.api.nvim_buf_set_extmark(self.buf, ns_state, i - 1, 0, {
        sign_text = "●",
        sign_hl_group = f.read_only and "DatabaseFormError" or "DatabaseFormChangedSign",
        line_hl_group = f.read_only and nil or "DatabaseFormChanged",
      })
    end
  end
  self.discard_armed = false
  self:resize()
end

function Form:resize()
  if not self:valid() then
    return
  end
  local max = math.max(3, vim.o.lines - 8)
  local ok, h = pcall(vim.api.nvim_win_text_height, self.win, {})
  local height = math.min(max, math.max(#self.fields, ok and h.all or #self.fields))
  if vim.api.nvim_win_get_height(self.win) ~= height then
    local cfg = vim.api.nvim_win_get_config(self.win)
    cfg.height = height
    cfg.row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
    vim.api.nvim_win_set_config(self.win, cfg)
  end
end

function Form:close()
  if self.preview_win and vim.api.nvim_win_is_valid(self.preview_win) then
    vim.api.nvim_win_close(self.preview_win, true)
  end
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  if vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_buf_delete(self.buf, { force = true })
  end
  if self.return_win and vim.api.nvim_win_is_valid(self.return_win) then
    vim.api.nvim_set_current_win(self.return_win)
  end
  if M.current == self then
    M.current = nil
  end
end

function Form:cancel()
  local changes = self:diff()
  if changes and #changes == 0 then
    return self:close()
  end
  if self.discard_armed then
    return self:close()
  end
  self.discard_armed = true
  notify("The row has changes: q again to discard them, <C-s> to apply them", vim.log.levels.WARN)
end

function Form:reset_line()
  local row = vim.api.nvim_win_get_cursor(self.win)[1]
  local f = self.fields[row]
  if f then
    vim.api.nvim_buf_set_lines(self.buf, row - 1, row, false, { sql.encode(f.original) })
  end
end

function Form:set_null()
  local row = vim.api.nvim_win_get_cursor(self.win)[1]
  local f = self.fields[row]
  if not f then
    return
  end
  if f.nullable == false then
    notify(f.name .. " cannot be NULL", vim.log.levels.WARN)
    return
  end
  vim.api.nvim_buf_set_lines(self.buf, row - 1, row, false, { "NULL" })
end

function Form:help()
  notify(table.concat(HELP, "\n"))
end

-- Show the UPDATE and wait for a yes.
function Form:submit()
  if vim.fn.mode() ~= "n" then
    vim.cmd.stopinsert()
  end
  local changes, err = self:diff()
  if not changes then
    notify(err, vim.log.levels.ERROR)
    return
  end
  if #changes == 0 then
    notify("Nothing changed")
    return self:close()
  end
  local statement = sql.update(self.conn.type, self.target, self.key, changes)
  self.statement = statement

  local lines = vim.split(statement, "\n")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "sql"
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local width = 30
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l) + 2)
  end
  width = math.min(width, vim.o.columns - 6)
  self.preview_win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = #lines,
    row = math.max(0, math.floor((vim.o.lines - #lines) / 2) - 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Apply this change? ",
    title_pos = "center",
    footer = " <CR> y  apply · n q <Esc>  back ",
    footer_pos = "center",
    zindex = 60,
  })
  vim.wo[self.preview_win].wrap = true
  local function back()
    if self.preview_win and vim.api.nvim_win_is_valid(self.preview_win) then
      vim.api.nvim_win_close(self.preview_win, true)
    end
    self.preview_win = nil
    if self:valid() then
      vim.api.nvim_set_current_win(self.win)
    end
  end
  local function apply()
    if self.applying then
      return
    end
    self.applying = true
    vim.api.nvim_win_set_config(
      self.preview_win,
      { footer = " applying… ", footer_pos = "center" }
    )
    M.backend.run(self.conn.id, statement, function(run_err, call)
      self.applying = false
      if run_err then
        back()
        notify("The change was not applied:\n" .. run_err, vim.log.levels.ERROR)
        return
      end
      local rows = call and M.backend.rows(call.id) or {}
      local affected = rows[1] and tonumber(as_text(rows[1]["Rows Affected"]))
      self:close()
      if affected == 0 then
        notify(
          "No row was changed: it may have been changed or deleted meanwhile",
          vim.log.levels.WARN
        )
      else
        notify(("%s: row updated"):format(sql.table_name(self.conn.type, self.target)))
      end
      if self.on_applied then
        self.on_applied()
      end
    end)
  end
  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true })
  end
  for _, lhs in ipairs({ "<CR>", "y", "<C-s>" }) do
    map(lhs, apply)
  end
  for _, lhs in ipairs({ "n", "q", "<Esc>" }) do
    map(lhs, back)
  end
end

function Form:open()
  set_highlights()
  local label_width = 0
  for _, f in ipairs(self.fields) do
    label_width = math.max(label_width, vim.fn.strdisplaywidth(f.name))
  end
  label_width = math.min(label_width, 32)

  local lines = {}
  local value_width = 20
  for i, f in ipairs(self.fields) do
    lines[i] = sql.encode(f.original)
    value_width = math.max(value_width, vim.fn.strdisplaywidth(lines[i]) + #f.type + 4)
  end
  local width = math.min(math.max(56, label_width + 3 + value_width + 2), vim.o.columns - 6)
  local height = math.min(#self.fields, math.max(3, vim.o.lines - 8))

  self.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  vim.bo[self.buf].buftype = "acwrite"
  vim.bo[self.buf].bufhidden = "wipe"
  vim.bo[self.buf].swapfile = false
  vim.bo[self.buf].undolevels = vim.o.undolevels
  vim.api.nvim_buf_set_name(
    self.buf,
    ("dbee-row://%s/%d"):format(self.target.table, vim.uv.hrtime() % 1000000)
  )
  vim.bo[self.buf].filetype = "dbee-row"
  vim.bo[self.buf].modified = false

  self.marks = {}
  for i, f in ipairs(self.fields) do
    local hl = f.key and "DatabaseFormKey"
      or (f.read_only and "DatabaseFormReadOnly" or "DatabaseFormLabel")
    local name = f.name
    if vim.fn.strdisplaywidth(name) > label_width then
      name = vim.fn.strcharpart(name, 0, label_width - 1) .. "…"
    end
    local pad = string.rep(" ", label_width - vim.fn.strdisplaywidth(name))
    local type_text = f.type
    if f.read_only then
      type_text = (type_text ~= "" and type_text .. " · " or "") .. f.read_only
    end
    self.marks[i] = vim.api.nvim_buf_set_extmark(self.buf, ns, i - 1, 0, {
      virt_text = { { name .. pad, hl }, { " │ ", "FloatBorder" } },
      virt_text_pos = "inline",
      right_gravity = false,
    })
    if type_text ~= "" then
      vim.api.nvim_buf_set_extmark(self.buf, ns, i - 1, 0, {
        virt_text = { { type_text, "DatabaseFormType" } },
        virt_text_pos = "right_align",
        hl_mode = "combine",
      })
    end
  end

  local title = (" Edit %s · %s "):format(
    sql.table_name(self.conn.type, self.target):gsub('[`"]', ""),
    table.concat(
      vim.tbl_map(function(k)
        return k.name .. "=" .. k.value
      end, self.key),
      ", "
    )
  )
  self.return_win = vim.api.nvim_get_current_win()
  self.win = vim.api.nvim_open_win(self.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = title,
    title_pos = "center",
    footer = " <C-s> apply · <C-n> NULL · gr reset · q close · ? help ",
    footer_pos = "center",
    zindex = 50,
  })
  local wo = vim.wo[self.win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "yes:1"
  wo.foldcolumn = "0"
  wo.wrap = true
  wo.breakindent = true
  wo.cursorline = true
  wo.spell = false
  wo.list = false
  wo.statuscolumn = ""
  wo.winbar = ""

  -- First editable value, so `cc`/`ciw` work right away.
  for i, f in ipairs(self.fields) do
    if not f.read_only then
      vim.api.nvim_win_set_cursor(self.win, { i, 0 })
      break
    end
  end

  local buf = self.buf
  local function map(modes, lhs, fn)
    vim.keymap.set(modes, lhs, fn, { buffer = buf, nowait = true })
  end
  local submit = function()
    self:submit()
  end
  map({ "n", "i" }, "<C-s>", submit)
  map({ "n", "i" }, "<D-s>", submit)
  map("n", "<CR>", submit)
  map("i", "<CR>", "<Esc>")
  map("n", "<C-n>", function()
    self:set_null()
  end)
  map("n", "gr", function()
    self:reset_line()
  end)
  map("n", "q", function()
    self:cancel()
  end)
  map("n", "<Esc>", function()
    self:cancel()
  end)
  map("n", "?", function()
    self:help()
  end)

  local group = vim.api.nvim_create_augroup("database_row_form_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = buf,
    callback = function()
      vim.bo[buf].modified = false
      vim.schedule(submit)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = buf,
    callback = function()
      self:refresh()
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(self.win),
    once = true,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
        if M.current == self then
          M.current = nil
        end
      end)
    end,
  })
  self:refresh()
  M.current = self
end

---Open the form for row `index` (1-based) of `call`, run on `conn`.
---@param conn ConnectionParams
---@param call CallDetails
---@param index integer
---@param on_applied? fun() called after the row was updated
function M.open(conn, call, index, on_applied)
  if M.current and M.current:valid() then
    vim.api.nvim_set_current_win(M.current.win)
    return
  end
  if not sql.dialects[conn.type] then
    return notify(
      ("Editing rows of a %s connection is not supported"):format(conn.type),
      vim.log.levels.WARN
    )
  end
  local target, why = sql.source_table(call.query)
  if not target then
    return notify("This row cannot be edited: " .. why, vim.log.levels.WARN)
  end
  local rows, err = M.backend.rows(call.id, index - 1, index)
  local row = rows and rows[1]
  if type(row) ~= "table" or vim.islist(row) then
    return notify("Could not read the row: " .. (err or "no row here"), vim.log.levels.ERROR)
  end
  M.backend.run(conn.id, sql.columns_query(conn.type, target), function(run_err, meta_call)
    if run_err then
      return notify("Could not read the columns of the table: " .. run_err, vim.log.levels.ERROR)
    end
    local columns = sql.columns(conn.type, M.backend.rows(meta_call.id) or {})
    if #columns == 0 then
      return notify(("Table %s was not found"):format(target.table), vim.log.levels.ERROR)
    end
    local key_cols = vim.tbl_filter(function(c)
      return c.key ~= nil
    end, columns)
    table.sort(key_cols, function(a, b)
      return a.key < b.key
    end)
    if #key_cols == 0 then
      return notify(
        ("This row cannot be edited: %s has no primary key"):format(target.table),
        vim.log.levels.WARN
      )
    end
    local key = {}
    for _, c in ipairs(key_cols) do
      local value = as_text(row[c.name])
      if value == nil then
        return notify(
          ("This row cannot be edited: add the primary key column %s to the SELECT"):format(c.name),
          vim.log.levels.WARN
        )
      end
      key[#key + 1] = { name = c.name, value = value }
    end
    local form = setmetatable({
      conn = conn,
      target = target,
      key = key,
      fields = build_fields(columns, row, target.table),
      on_applied = on_applied,
    }, Form)
    form:open()
  end)
end

return M
