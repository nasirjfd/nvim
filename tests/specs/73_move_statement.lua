local lib = require("lib")
local h = require("support")

local PHP = {
  "<?php",
  "class Example",
  "{",
  "    /** First method. */",
  "    public function first()",
  "    {",
  "        firstCall();",
  "        secondCall();",
  "    }",
  "",
  "    /** Second method. */",
  "    public function second()",
  "    {",
  "        return 2;",
  "    }",
  "}",
}

local function editor(lines, file)
  local dir = h.tmpdir()
  h.write(dir .. "/" .. (file or "example.php"), lines)
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit " .. (file or "example.php") .. "')")
  h.wait(screen, function()
    return screen:exec(
      "local ok, p = pcall(vim.treesitter.get_parser, 0); return ok and p:parse()[1] ~= nil"
    )
  end, "syntax parser did not load")
  return screen
end

lib.test(
  "Ctrl J and K swap whole PHP methods with documentation and preserve cursor and undo",
  function()
    local screen = editor(PHP)
    screen:exec([[
    vim.api.nvim_win_set_cursor(0, { 5, 20 })
    vim.fn.setreg('"', 'keep this')
    _G.statement_win = vim.api.nvim_get_current_win()
    vim.cmd('split')
    vim.api.nvim_set_current_win(_G.statement_win)
  ]])
    screen:input("<C-j>")
    local moved = vim.list_extend(vim.list_slice(PHP, 1, 3), vim.list_slice(PHP, 11, 15))
    vim.list_extend(moved, { "" })
    vim.list_extend(moved, vim.list_slice(PHP, 4, 9))
    vim.list_extend(moved, { "}" })
    h.wait(screen, function()
      return screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")[5]
        == "    public function second()"
    end, "Ctrl+J did not move the whole first method down")
    lib.eq(moved, screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
    lib.eq({ 11, 20 }, screen:exec("return vim.api.nvim_win_get_cursor(0)"))
    lib.ok(screen:exec("return vim.api.nvim_get_current_win() == _G.statement_win"))
    lib.eq("keep this", screen:exec([[return vim.fn.getreg('"')]]))
    screen:input("u")
    h.wait(screen, function()
      return vim.deep_equal(PHP, screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
    end, "one undo did not restore the method swap")
    screen:exec("vim.api.nvim_win_set_cursor(0, { 12, 20 })")
    screen:input("<C-k>")
    h.wait(screen, function()
      return vim.deep_equal(
        moved,
        screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
      )
    end, "Ctrl+K did not move the second method up")
    screen:close()
  end
)

lib.test(
  "statement movement swaps nested statements without moving their enclosing method",
  function()
    local screen = editor(PHP)
    screen:exec("vim.api.nvim_win_set_cursor(0, { 7, 10 })")
    screen:input("<C-j>")
    h.wait(screen, function()
      return screen:exec(
        "return vim.api.nvim_buf_get_lines(0, 6, 7, false)[1] == '        secondCall();'"
      )
    end, "Ctrl+J did not move the statement inside the method")
    lib.eq(
      "    public function first()",
      screen:exec("return vim.api.nvim_buf_get_lines(0, 4, 5, false)[1]")
    )
    screen:input("<C-k>")
    h.wait(screen, function()
      return vim.deep_equal(PHP, screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
    end, "Ctrl+K did not restore the nested statements")
    screen:close()
  end
)

for _, case in ipairs({
  {
    "lua",
    {},
    { "-- First", "local function first()", "  return 1", "end" },
    { "-- Second", "local function second()", "  return 2", "end" },
  },
  {
    "py",
    {},
    { "@first_decorator", "def first():", "    return 1" },
    { "@second_decorator", "def second():", "    return 2" },
  },
  {
    "js",
    {},
    { "// First", "function first() {", "  return 1;", "}" },
    { "// Second", "function second() {", "  return 2;", "}" },
  },
  {
    "ts",
    {},
    { "// First", "function first(): number {", "  return 1;", "}" },
    { "// Second", "function second(): number {", "  return 2;", "}" },
  },
  {
    "go",
    { "package example", "" },
    { "// First", "func first() int {", "  return 1", "}" },
    { "// Second", "func second() int {", "  return 2", "}" },
  },
  {
    "rs",
    {},
    { "#[inline]", "fn first() -> i32 {", "    1", "}" },
    { "#[inline]", "fn second() -> i32 {", "    2", "}" },
  },
  {
    "c",
    {},
    { "// First", "int first(void) {", "  return 1;", "}" },
    { "// Second", "int second(void) {", "  return 2;", "}" },
  },
  {
    "sh",
    {},
    { "# First", "first() {", "  echo first", "}" },
    { "# Second", "second() {", "  echo second", "}" },
  },
  {
    "swift",
    {},
    { "// First", "func first() -> Int {", "    return 1", "}" },
    { "// Second", "func second() -> Int {", "    return 2", "}" },
  },
}) do
  lib.test("statement movement swaps functions in " .. case[1], function()
    local function contents(first, second)
      local lines = vim.deepcopy(case[2])
      vim.list_extend(lines, first)
      vim.list_extend(lines, { "" })
      return vim.list_extend(lines, second)
    end
    local original = contents(case[3], case[4])
    local moved = contents(case[4], case[3])
    local screen = editor(original, "example." .. case[1])
    screen:exec("vim.api.nvim_win_set_cursor(0, { ..., 0 })", { #case[2] + 2 })
    screen:input("<C-j>")
    h.wait(screen, function()
      return vim.deep_equal(
        moved,
        screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
      )
    end, "Ctrl+J did not swap " .. case[1] .. " functions with their comments/attributes")
    screen:input("<C-k>")
    h.wait(screen, function()
      return vim.deep_equal(
        original,
        screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
      )
    end, function()
      return "Ctrl+K did not restore "
        .. case[1]
        .. " functions: "
        .. vim.inspect(screen:exec([[
          local ranges = {}
          for child in vim.treesitter.get_parser():parse()[1]:root():iter_children() do
            ranges[#ranges + 1] = { child:type(), child:range() }
          end
          return { map = vim.fn.maparg('<C-k>', 'n', false, true).desc, ranges = ranges,
            node = vim.treesitter.get_node():sexpr(),
            tree = vim.treesitter.get_parser():parse()[1]:root():sexpr() }
        ]]))
    end)
    screen:close()
  end)
end

lib.test(
  "statement movement stops at scope boundaries and leaves read-only buffers unchanged",
  function()
    local screen = editor(PHP)
    screen:exec("vim.api.nvim_win_set_cursor(0, { 5, 10 }); vim.v.errmsg = ''")
    screen:input("<C-k>")
    lib.eq(PHP, screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
    screen:exec("vim.bo.readonly = true; vim.bo.modifiable = false")
    screen:input("<C-j><C-k>")
    lib.eq(PHP, screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
    lib.eq("", screen:exec("return vim.v.errmsg"))
    screen:close()
  end
)

lib.test("LSP attach keeps Ctrl K statement movement and Insert signature help", function()
  local screen = editor(PHP)
  screen:exec([[
    local get_client = vim.lsp.get_client_by_id
    vim.lsp.get_client_by_id = function() return { supports_method = function() return false end } end
    local handler = vim.api.nvim_get_autocmds({ group = 'UserLspConfig', event = 'LspAttach' })[1].callback
    handler({ buf = vim.api.nvim_get_current_buf(), data = { client_id = -1 } })
    vim.lsp.get_client_by_id = get_client
  ]])
  lib.eq("Move Statement Up", screen:exec("return vim.fn.maparg('<C-k>', 'n', false, true).desc"))
  lib.eq("Signature Help", screen:exec("return vim.fn.maparg('<C-k>', 'i', false, true).desc"))
  screen:exec("vim.api.nvim_win_set_cursor(0, { 12, 0 })")
  screen:input("<C-k>")
  h.wait(screen, function()
    return screen:exec(
      "return vim.api.nvim_buf_get_lines(0, 4, 5, false)[1] == '    public function second()'"
    )
  end, "LSP attach overrode Ctrl+K")
  screen:close()
end)

lib.test("statement movement counts stop at boundaries and undo as one edit", function()
  local lines = {
    "local function one() return 1 end",
    "",
    "local function two() return 2 end",
    "",
    "local function three() return 3 end",
  }
  local screen = editor(lines, "example.lua")
  screen:input("3<C-j>")
  h.wait(screen, function()
    return screen:exec("return vim.api.nvim_buf_get_lines(0, -2, -1, false)[1]") == lines[1]
  end, "counted movement did not stop after moving past both neighbors")
  screen:input("u")
  h.wait(screen, function()
    return vim.deep_equal(lines, screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
  end, "counted swaps were not a single undo step")
  screen:close()
end)

lib.test("statement movement without a parser does not fall back to splitting lines", function()
  local dir = h.tmpdir()
  local lines = { "not code", "keep this text" }
  h.write(dir .. "/example.txt", lines)
  local screen = h.nvim(dir)
  screen:exec("vim.cmd('edit example.txt'); vim.v.errmsg = ''")
  screen:input("<C-j><C-k>")
  lib.eq(lines, screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
  lib.eq("", screen:exec("return vim.v.errmsg"))
  screen:close()
end)
