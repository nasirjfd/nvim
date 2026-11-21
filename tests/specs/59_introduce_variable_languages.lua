-- Introduce Variable (Cmd+Option+V) in TypeScript, JavaScript, Go, Lua and Python: the same engine
-- as PHP with each language's declaration, name style and suggestions.
local lib = require("lib")
local h = require("support")

-- Select `selected` (the `nth` match) in a buffer of `filetype`, press Cmd+Option+V and answer the
-- name prompt with `answer` (nil: accept the suggestion). Returns the lines, the suggestion and the
-- notifications.
local function extract(filetype, lines, selected, answer, nth)
  local screen = h.nvim(h.tmpdir())
  local result = screen:exec(
    [[
    local filetype, lines, selected, answer, nth = ...
    vim.g.autosave = false
    vim.cmd('enew')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.filetype = filetype
    _G.prompts, _G.notes = {}, {}
    vim.ui.input = function(opts, callback)
      table.insert(_G.prompts, opts)
      callback(answer ~= vim.NIL and answer or opts.default)
    end
    vim.notify = function(message) table.insert(_G.notes, message) end
    local source = table.concat(lines, '\n')
    local first, last = 0, 0
    for _ = 1, nth do
      first, last = source:find(selected, last + 1, true)
    end
    local function position(offset)
      local before = vim.split(source:sub(1, offset - 1), '\n', { plain = true })
      return { #before, #before[#before] }
    end
    vim.api.nvim_win_set_cursor(0, position(first))
    vim.cmd('normal! v')
    vim.api.nvim_win_set_cursor(0, position(last))
    require('core.introduce-variable').extract()
    return {
      lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
      suggestion = _G.prompts[1] and _G.prompts[1].default or false,
      prompted = #_G.prompts,
      notes = _G.notes,
    }
  ]],
    { filetype, lines, selected, answer or vim.NIL, nth or 1 }
  )
  screen:close()
  return result
end

local cases = {
  -- TypeScript: const, a semicolon only where the file uses them, camelCase names
  {
    "typescript: a method call is named without its get",
    "typescript",
    { "function f(req) {", "  return req.getContent().trim();", "}" },
    "req.getContent()",
    { "function f(req) {", "  const content = req.getContent();", "  return content.trim();", "}" },
  },
  {
    "typescript: no semicolon where the statement has none",
    "typescript",
    { "function f(price, qty) {", "  const total = price * qty", "}" },
    "price * qty",
    { "function f(price, qty) {", "  const amount = price * qty", "  const total = amount", "}" },
    "amount",
  },
  {
    "typescript: an object value is named after its key",
    "typescript",
    { "function f() {", "  send({ user_id: compute() });", "}" },
    "compute()",
    { "function f() {", "  const userId = compute();", "  send({ user_id: userId });", "}" },
  },
  {
    "typescript: a call on its own line becomes the declaration",
    "typescript",
    { "function f() {", "  new ApiClient(url);", "}" },
    "new ApiClient(url)",
    { "function f() {", "  const apiClient = new ApiClient(url);", "}" },
  },
  {
    "javascript: a string index is named after the key",
    "javascript",
    { "function f(env) {", "  return env['REQUEST_TIME'] * 1000;", "}" },
    "env['REQUEST_TIME']",
    { "function f(env) {", "  const requestTime = env['REQUEST_TIME'];", "  return requestTime * 1000;", "}" },
  },
  -- Go: :=, camelCase, a struct literal named after its type
  {
    "go: a selector call is named without its Get",
    "go",
    { "package m", "", "func f(r R) int {", "\treturn len(r.GetBody())", "}" },
    "r.GetBody()",
    { "package m", "", "func f(r R) int {", "\tbody := r.GetBody()", "\treturn len(body)", "}" },
  },
  {
    "go: a struct literal is named after its type",
    "go",
    { "package m", "", "func f() {", "\tsave(Order{ID: 1})", "}" },
    "Order{ID: 1}",
    { "package m", "", "func f() {", "\torder := Order{ID: 1}", "\tsave(order)", "}" },
  },
  -- Lua: local, snake_case
  {
    "lua: a method call becomes a snake_case local",
    "lua",
    { "local function f(buf)", "  return #vim.api.nvim_buf_get_lines(buf, 0, -1, false)", "end" },
    "vim.api.nvim_buf_get_lines(buf, 0, -1, false)",
    {
      "local function f(buf)",
      "  local nvim_buf_get_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)",
      "  return #nvim_buf_get_lines",
      "end",
    },
  },
  {
    "lua: a table field value is named after the field",
    "lua",
    { "local function f()", "  setup({ maxWidth = compute() })", "end" },
    "compute()",
    { "local function f()", "  local max_width = compute()", "  setup({ maxWidth = max_width })", "end" },
  },
  -- Python: snake_case, keyword arguments
  {
    "python: a keyword argument value is named after the keyword",
    "python",
    { "def f(a):", "    return send(a, timeout=compute(a))" },
    "compute(a)",
    { "def f(a):", "    timeout = compute(a)", "    return send(a, timeout=timeout)" },
  },
  {
    "python: a class call is named in snake_case and numbered when taken",
    "python",
    { "def f(api_client):", "    return use(ApiClient(1))" },
    "ApiClient(1)",
    { "def f(api_client):", "    api_client2 = ApiClient(1)", "    return use(api_client2)" },
  },
}

for _, case in ipairs(cases) do
  lib.test("introduce variable: " .. case[1], function()
    local result = extract(case[2], case[3], case[4], case[6])
    lib.eq({}, result.notes, "unexpected warning")
    lib.eq(case[5], result.lines)
  end)
end

-- Refused: moving the value would change what runs or when.
for _, case in ipairs({
  { "typescript", { "function f(a, b) {", "  return a && b.load();", "}" }, "b.load()" },
  { "typescript", { "function f(a) {", "  return a?.b.load(1);", "}" }, "a?.b" },
  { "typescript", { "function f(a) {", "  return a ? load() : 0;", "}" }, "load()" },
  { "typescript", { "function f() {", "  return first() + second();", "}" }, "second()" },
  { "typescript", { "function f(x) {", "  x = compute();", "}" }, "x" },
  { "go", { "package m", "", "func f(a bool) bool {", "\treturn a || load()", "}" }, "load()" },
  { "lua", { "local function f(a)", "  return a or load()", "end" }, "load()" },
  { "lua", { "local function f()", "  for i = 1, count() do end", "end" }, "count()" },
  { "python", { "def f(a):", "    return a or load()" }, "load()" },
  { "python", { "def f(xs):", "    return [load(x) for x in xs]" }, "load(x)" },
  { "python", { "def f():", "    return lambda: load()" }, "load()" },
}) do
  lib.test("introduce variable: " .. case[1] .. " refuses " .. case[3], function()
    local result = extract(case[1], case[2], case[3], "name")
    lib.eq(case[2], result.lines, "the code changed")
    lib.eq(0, result.prompted, "the name was asked for")
    lib.eq(1, #result.notes, "no reason was shown")
  end)
end

lib.test("introduce variable: names are checked per language", function()
  for _, case in ipairs({
    { "typescript", { "function f() {", "  return load();", "}" }, "load()", "class" },
    { "go", { "package m", "", "func f() int {", "\treturn load()", "}" }, "load()", "func" },
    { "lua", { "local function f()", "  return load()", "end" }, "load()", "end" },
    { "python", { "def f():", "    return load()" }, "load()", "lambda" },
  }) do
    local result = extract(case[1], case[2], case[3], case[4])
    lib.eq(case[2], result.lines, case[1] .. " accepted the keyword " .. case[4])
    lib.ok(result.notes[1] and result.notes[1]:find("variable name", 1, true), "no name error for " .. case[1])
  end
end)
