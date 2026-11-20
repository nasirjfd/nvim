local lib = require("lib")
local h = require("support")

-- dbee + the row edit form (lua/modules/database) against a real SQLite database: dbee's own backend runs
-- the queries, so this is the same path as a MySQL connection, only the dialect differs.

lib.test("database: which table a query reads, values in the form, the UPDATE", function()
  local screen = h.nvim(h.tmpdir())
  local r = screen:exec([[
    local sql = require("modules.database.sql")
    local function t(q) local v, why = sql.source_table(q); return v or why end
    return {
      t("SELECT * FROM `db`.`orders` o WHERE note = 'a join b' LIMIT 10;"),
      t("select id from users -- join\n order by id"),
      t("select * from a join b on a.id = b.id"),
      t("select * from a, b"),
      t("update a set x = 1"),
      sql.update("mysql", { schema = "db", table = "t" }, { { name = "id", value = "5" } },
        { { name = "a", value = "it's" }, { name = "b" }, { name = "c", value = "a\\b" } }),
      sql.update("sqlite", { table = "t" }, { { name = "id", value = "5" } }, { { name = "a", value = "x" } }),
      sql.encode("a\nb\\c"), sql.decode(sql.encode("a\nb\\c")) == "a\nb\\c",
      sql.encode(nil), sql.decode("NULL") == nil, sql.encode("NULL"), sql.decode("\\NULL"),
    }
  ]])
  lib.eq({ schema = "db", table = "orders" }, r[1])
  lib.eq({ table = "users" }, r[2])
  lib.matches("JOIN", r[3])
  lib.matches("more than one table", r[4])
  lib.matches("only the rows of a SELECT", r[5])
  lib.eq(
    "UPDATE `db`.`t`\nSET `a` = 'it''s',\n    `b` = NULL,\n    `c` = _utf8mb4 X'615C62'\nWHERE `id` = '5'\nLIMIT 1",
    r[6]
  )
  lib.eq('UPDATE "t"\nSET "a" = \'x\'\nWHERE "id" = \'5\'', r[7])
  lib.eq("a\\nb\\\\c", r[8])
  lib.ok(r[9], "a newline and a backslash survive the form")
  lib.eq("NULL", r[10])
  lib.ok(r[11], "NULL is read back as NULL")
  lib.eq("\\NULL", r[12])
  lib.eq("NULL", r[13])
  screen:close()
end)

lib.test("database: connections of a Supernova mysql.yml, commented blocks included", function()
  local dir = h.tmpdir()
  h.write(dir .. "/mysql.yml", {
    "# mysql:",
    "#   default:",
    "#     uri: mysql:host=mysql;port=3306;dbname=app;charset=utf8mb4",
    "#     user: root",
    "#     pass: root",
    "",
    "mysql:",
    "  default:",
    "    uri: mysql:host=10.0.0.1;port=13306;dbname=app;charset=utf8mb4",
    "    user: me",
    "    pass: secret",
    "  app_log:",
    "    uri: mysql:host=10.0.0.1;port=13306;dbname=app_log;charset=utf8mb4",
    "    user: me",
    "    pass: secret",
  })
  local screen = h.nvim(dir)
  local list = screen:exec(
    [[return require("modules.database.mysql_yml").connections(..., {
      mysql = { name = "mysql_local", host = "127.0.0.1", port = 3307 },
      ["10.0.0.1"] = { name = "mysql_demo" },
    })]],
    { dir .. "/mysql.yml" }
  )
  lib.eq({
    { name = "mysql_demo", type = "mysql", url = "me:secret@tcp(10.0.0.1:13306)/app" },
    { name = "mysql_local", type = "mysql", url = "root:root@tcp(127.0.0.1:3307)/app" },
  }, list)
  screen:close()
end)

local function sqlite(db, statement)
  -- the editor may be writing the same database at that moment: wait for its lock, do not fail on it
  local out = vim.system({ "sqlite3", "-cmd", ".timeout 5000", db, statement }, { text = true }):wait()
  assert(out.code == 0, out.stderr)
  return vim.trim(out.stdout)
end

local function form_lines(screen)
  return screen:exec([[
    local f = require("modules.database.form").current
    return f and f:valid() and vim.api.nvim_buf_get_lines(f.buf, 0, -1, false) or false
  ]])
end

-- dbee open on a fresh SQLite database, the result of `query` in the result pane, cursor on row `row`.
local function open_result(query, row)
  local dir = h.tmpdir()
  local db = dir .. "/app.db"
  sqlite(
    db,
    "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, note TEXT);"
      .. "INSERT INTO users VALUES (1, 'ada', 'first'), (2, 'bob', NULL), (3, 'cy', 'x'), (4, 'می‌خواهم', 'y');"
      .. "CREATE TABLE logs (msg TEXT);"
      .. "INSERT INTO logs VALUES ('hi');"
  )
  local screen = h.nvim(dir)
  screen:exec(
    [[require("modules.database").configure({ name = "test",
      connections = { { name = "sqlite_test", type = "sqlite", url = ... } } })]],
    { db }
  )
  screen:command("Dbee")
  h.wait(screen, function()
    return screen:exec([[
      local ok, api = pcall(require, "dbee.api")
      if not ok or not api.core.is_loaded() then return false end
      for _, c in ipairs(api.core.source_get_connections("test")) do
        if c.name == "sqlite_test" then api.core.set_current_connection(c.id); return true end
      end
      return false
    ]])
  end, "the project connection is not listed in dbee")
  screen:exec("require('dbee').execute(...)", { query })
  h.wait(screen, function()
    return screen:exec([[
      local c = require("dbee.api").ui.result_get_call()
      return c ~= nil and c.state == "archived"
    ]])
  end, "the query did not finish")
  -- the result pane, cursor on the row
  h.wait(screen, function()
    return screen:exec(
      [[
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local b = vim.api.nvim_win_get_buf(w)
        if vim.api.nvim_buf_get_name(b):find("dbee%-result") then
          for l, text in ipairs(vim.api.nvim_buf_get_lines(b, 0, -1, false)) do
            if text:match("^%s*" .. ... .. "%s") then
              vim.api.nvim_set_current_win(w)
              vim.api.nvim_win_set_cursor(w, { l, 4 })
              return true
            end
          end
        end
      end
      return false
    ]],
      { tostring(row) }
    )
  end, "the result pane does not show the row")
  return screen, db
end

lib.test("database: e on a result row edits it in a form and applies the UPDATE", function()
  local screen, db = open_result("SELECT * FROM users ORDER BY id", 2)
  screen:input("e")
  h.wait(screen, function()
    return form_lines(screen)
  end, "the edit form did not open")
  lib.eq({ "2", "bob", "NULL" }, form_lines(screen))
  -- labels in front of the values, the title names the table and the key
  h.wait(screen, function()
    return h.find_on_screen(screen, "Edit users · id=2")
      and h.find_on_screen(screen, "name │ bob")
  end, "the form does not show its labels")
  -- the cursor starts on the first editable value: name (id is the primary key)
  lib.eq(2, screen:exec("return vim.api.nvim_win_get_cursor(0)[1]"))
  screen:input("ccbobby<Esc>j<C-n>")
  h.wait(screen, function()
    local l = form_lines(screen)
    return l and l[2] == "bobby"
  end, "the value was not edited")
  -- note is already NULL: set it to text instead
  screen:input("ccline1\\nline2<Esc>")
  screen:input("<C-s>")
  h.wait(screen, function()
    return h.find_on_screen(screen, "Apply this change?")
  end, "the UPDATE was not shown before applying")
  lib.ok(h.find_on_screen(screen, [[SET "name" = 'bobby',]]), "the UPDATE sets the changed values")
  lib.ok(
    h.find_on_screen(screen, [[WHERE "id" = '2']]),
    "the UPDATE finds the row by its primary key"
  )
  screen:input("<CR>")
  h.wait(screen, function()
    return sqlite(db, "SELECT name || '|' || note FROM users WHERE id = 2") == "bobby|line1\nline2"
  end, function()
    return "the row was not updated: "
      .. sqlite(db, "SELECT name || '|' || note FROM users WHERE id = 2")
  end)
  lib.eq("ada|first", sqlite(db, "SELECT name || '|' || note FROM users WHERE id = 1"))
  -- the form closed and the result pane shows the new value again
  h.wait(screen, function()
    return not form_lines(screen) and h.find_on_screen(screen, "bobby")
  end, "the result was not reloaded")
  screen:close()
end)

lib.test("database: the form refuses what it cannot write and closes without changes", function()
  local screen, db = open_result("SELECT * FROM users ORDER BY id", 1)
  screen:input("e")
  h.wait(screen, function()
    return form_lines(screen)
  end, "the edit form did not open")
  -- the primary key is read only
  screen:input("ggcc9<Esc><C-s>")
  h.wait(screen, function()
    return screen:exec([[
      for _, m in ipairs(require("snacks").notifier.get_history()) do
        if tostring(m.msg):find("cannot be changed: id") then return true end
      end
      return false
    ]])
  end, "editing the primary key was not refused")
  -- a deleted line is caught
  screen:input("grjdd<C-s>")
  h.wait(screen, function()
    return screen:exec([[
      for _, m in ipairs(require("snacks").notifier.get_history()) do
        if tostring(m.msg):find("added or removed") then return true end
      end
      return false
    ]])
  end, "a removed line was not caught")
  screen:input("u")
  h.wait(screen, function()
    local l = form_lines(screen)
    return l and #l == 3
  end, "undo did not bring the line back")
  -- q with changes asks once, closes the second time; nothing was written
  screen:input("j")
  screen:input("ccchanged<Esc>q")
  h.wait(screen, function()
    return screen:exec([[
      for _, m in ipairs(require("snacks").notifier.get_history()) do
        if tostring(m.msg):find("q again to discard") then return true end
      end
      return false
    ]])
  end, "q with changes did not ask first")
  lib.ok(form_lines(screen), "the form closed on the first q despite changes")
  screen:input("q")
  h.wait(screen, function()
    return not form_lines(screen)
  end, "the second q did not close the form")
  lib.eq("ada", sqlite(db, "SELECT name FROM users WHERE id = 1"))
  screen:close()
end)

lib.test("database: rows without a usable primary key are not editable", function()
  local screen = open_result("SELECT name FROM users ORDER BY id", 1)
  screen:input("e")
  h.wait(screen, function()
    return screen:exec([[
      for _, m in ipairs(require("snacks").notifier.get_history()) do
        if tostring(m.msg):find("add the primary key column id") then return true end
      end
      return false
    ]])
  end, "a row without its primary key was not refused")
  lib.ok(not form_lines(screen), "a form opened for a row without its primary key")
  screen:close()
end)

lib.test(
  "database: Persian values in the result pane read right to left, columns stay aligned",
  function()
    local screen = open_result("SELECT * FROM users ORDER BY id", 1)
    -- the value of row 4 (with a ZWNJ) is drawn in reading order: joined letters, right to left
    h.wait(screen, function()
      return h.find_on_screen(screen, "ﻢﻫﺍﻮﺧﯽﻣ") ~= nil
    end, "the Persian value is not drawn right to left in the result pane")
    -- the column after it starts where it starts on the other rows
    local row4 = h.find_on_screen(screen, "ﻢﻫﺍﻮﺧﯽﻣ")
    local row3 = h.find_on_screen(screen, "│ cy ")
    local x_col = row3 and h.find_on_row(screen, row3, "│ x")
    local y_col = h.find_on_row(screen, row4, "│ y")
    lib.ok(x_col and y_col, "rows 3 and 4 do not show their note\n" .. h.snapshot(screen))
    lib.eq(x_col, y_col, "the column after the Persian value moved")
    screen:close()
  end
)
