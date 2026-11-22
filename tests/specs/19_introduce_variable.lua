local lib = require("lib")
local h = require("support")

local function editor(lines, text, name, backwards)
  local screen = h.nvim(h.tmpdir())
  screen:exec(
    [[
    vim.g.autosave = false
    vim.opt.clipboard = ''
    vim.cmd('enew')
    local lines, selected, name, backwards = ...
    vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
    vim.bo.filetype = 'php'
    _G.variable_prompts, _G.variable_notes = {}, {}
    _G.original_variable_input = vim.ui.input
    vim.ui.input = function(opts, callback)
      table.insert(_G.variable_prompts, opts)
      callback(name ~= vim.NIL and name or nil)
    end
    vim.notify = function(message) table.insert(_G.variable_notes, message) end
    local source = table.concat(lines, '\n')
    local first, last = assert(source:find(selected, 1, true))
    local function position(offset)
      local before = vim.split(source:sub(1,offset-1),'\n',{plain=true})
      return {#before, #before[#before]}
    end
    local start, finish = position(first), position(last)
    vim.api.nvim_win_set_cursor(0, backwards and finish or start)
    vim.cmd('normal! v')
    vim.api.nvim_win_set_cursor(0, backwards and start or finish)
  ]],
    { lines, text, name or vim.NIL, backwards or false }
  )
  return screen
end

local function extract(screen)
  screen:input("<D-M-v>")
  vim.wait(80)
end

local function lines(screen)
  return screen:exec("return vim.api.nvim_buf_get_lines(0,0,-1,false)")
end

lib.test("introduce variable: Cmd+Option+V extracts only the selected PHP expression", function()
  local source = { "<?php", "function demo($id) {", "    return find($id, [2009, 2253]);", "}" }
  local screen = editor(source, "[2009, 2253]", "bucketIds")
  extract(screen)
  lib.eq({
    "<?php",
    "function demo($id) {",
    "    $bucketIds = [2009, 2253];",
    "    return find($id, $bucketIds);",
    "}",
  }, lines(screen))
  lib.eq(1, screen:exec("return #_G.variable_prompts"))
  screen:input("u")
  h.wait(screen, function()
    return vim.deep_equal(source, lines(screen))
  end, "extraction was not one undo step")
  screen:close()
end)

lib.test("introduce variable: accepts a dollar-prefixed name and a backward selection", function()
  local screen = editor(
    { "<?php", "function demo($x) {", "    return calculate($x) + 1;", "}" },
    "calculate($x)",
    "$amount",
    true
  )
  extract(screen)
  lib.eq({
    "<?php",
    "function demo($x) {",
    "    $amount = calculate($x);",
    "    return $amount + 1;",
    "}",
  }, lines(screen))
  screen:close()
end)

lib.test("introduce variable: a standalone expression becomes an assignment", function()
  local screen = editor(
    { "<?php", "function demo($x) {", "    calculate($x); // keep comment", "}" },
    "calculate($x);",
    "amount"
  )
  extract(screen)
  lib.eq(
    { "<?php", "function demo($x) {", "    $amount = calculate($x); // keep comment", "}" },
    lines(screen)
  )
  screen:close()
end)

lib.test("introduce variable: multiline expressions retain indentation", function()
  local screen = editor({
    "<?php",
    "function demo($x) {",
    "    return calculate(",
    "        $x,",
    "        2",
    "    );",
    "}",
  }, "calculate(\n        $x,\n        2\n    )", "amount")
  extract(screen)
  lib.eq({
    "<?php",
    "function demo($x) {",
    "    $amount = calculate(",
    "        $x,",
    "        2",
    "    );",
    "    return $amount;",
    "}",
  }, lines(screen))
  screen:close()
end)

lib.test("introduce variable: multiline string contents are preserved verbatim", function()
  local screen = editor({
    "<?php",
    "function demo() {",
    "    return accept(",
    "        'first",
    "        second'",
    "    );",
    "}",
  }, "'first\n        second'", "label")
  extract(screen)
  lib.eq({
    "<?php",
    "function demo() {",
    "    $label = 'first",
    "        second';",
    "    return accept(",
    "        $label",
    "    );",
    "}",
  }, lines(screen))
  screen:close()
end)

for _, case in ipairs({
  { "while (poll()) {", "poll()" },
  { "return $ready && calculate();", "calculate()" },
  { "return accept(first(), second());", "second()" },
  { "$target = 1;", "$target" },
  { "return calculate();", "alcul" },
}) do
  lib.test("introduce variable: rejects unsafe selection in " .. case[1], function()
    local source = { "<?php", "function demo() {", "    " .. case[1], "}" }
    if case[1]:find("^while") then
      source[#source + 1] = "}"
    end
    local screen = editor(source, case[2], "value")
    extract(screen)
    lib.eq(source, lines(screen), "unsafe extraction changed the buffer")
    lib.eq(0, screen:exec("return #_G.variable_prompts"))
    lib.eq(1, screen:exec("return #_G.variable_notes"))
    screen:close()
  end)
end

for _, name in ipairs({ "existing", "bad name", "$this" }) do
  lib.test("introduce variable: rejects invalid or conflicting name " .. name, function()
    local source = { "<?php", "function demo($existing) {", "    return calculate();", "}" }
    local screen = editor(source, "calculate()", name)
    extract(screen)
    lib.eq(source, lines(screen))
    lib.eq(1, screen:exec("return #_G.variable_notes"))
    screen:close()
  end)
end

lib.test("introduce variable: cancellation does not change text or clipboard registers", function()
  local source = { "<?php", "function demo() {", "    return calculate();", "}" }
  local screen = editor(source, "calculate()", nil)
  screen:exec("vim.fn.setreg('a','keep clipboard'); vim.fn.setreg('\"',{points_to='a'})")
  extract(screen)
  lib.eq(source, lines(screen))
  lib.eq("keep clipboard", screen:exec("return vim.fn.getreg('\"')"))
  screen:close()
end)

lib.test("introduce variable: a changed buffer cancels a stale extraction", function()
  local source = { "<?php", "function demo() {", "    return calculate();", "}" }
  local screen = editor(source, "calculate()", "amount")
  screen:exec([[
    vim.ui.input = function(_, callback)
      vim.api.nvim_buf_set_lines(0,-1,-1,false,{'// newer edit'})
      callback('amount')
    end
  ]])
  extract(screen)
  lib.eq(
    { "<?php", "function demo() {", "    return calculate();", "}", "// newer edit" },
    lines(screen)
  )
  lib.eq(1, screen:exec("return #_G.variable_notes"))
  screen:close()
end)

lib.test("introduce variable: the real name prompt applies the extraction after Enter", function()
  local screen = editor(
    { "<?php", "function demo() {", "    return calculate();", "}" },
    "calculate()",
    "unused"
  )
  screen:exec("vim.ui.input = _G.original_variable_input")
  screen:input("<D-M-v>")
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'snacks_input' and vim.fn.mode() == 'i'")
  end, "variable name prompt did not open")
  screen:input("<C-u>amount<CR>")
  h.wait(screen, function()
    return vim.deep_equal(
      { "<?php", "function demo() {", "    $amount = calculate();", "    return $amount;", "}" },
      lines(screen)
    )
  end, "Enter did not introduce the named variable")
  screen:close()
end)

lib.test("introduce variable: without a suggestion the name starts empty, an empty Enter is an error", function()
  local source = { "<?php", "function demo() {", "    return 1 + 2;", "}" }
  local screen = editor(source, "1 + 2", "unused")
  screen:exec("vim.ui.input = _G.original_variable_input")
  local function prompt_open()
    return screen:exec("return vim.bo.filetype == 'snacks_input' and vim.fn.mode() == 'i'")
  end
  screen:input("<D-M-v>")
  h.wait(screen, prompt_open, "variable name prompt did not open")
  lib.eq({ "" }, screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"), "the name is not empty")
  screen:input("<CR>")
  h.wait(screen, function()
    return screen:exec("return _G.variable_notes[1]") == "Enter a variable name"
  end, "an empty name did not show an error")
  h.wait(screen, prompt_open, "the prompt did not come back after the empty name")
  screen:input("amount<CR>")
  h.wait(screen, function()
    return vim.deep_equal(
      { "<?php", "function demo() {", "    $amount = 1 + 2;", "    return $amount;", "}" },
      lines(screen)
    )
  end, "the typed name was not used")
  lib.eq(1, screen:exec("return #_G.variable_notes"))
  screen:close()
end)

lib.test("introduce variable: one Esc closes the name prompt and changes nothing", function()
  local source = { "<?php", "function demo() {", "    return calculate();", "}" }
  local screen = editor(source, "calculate()", "unused")
  screen:exec("vim.ui.input = _G.original_variable_input")
  for _, typed in ipairs({ "", "amo" }) do
    screen:input("<Esc>")
    screen:exec([[
      local first, last = vim.fn.getline(3):find('calculate()', 1, true)
      vim.api.nvim_win_set_cursor(0, {3, first - 1}); vim.cmd('normal! v')
      vim.api.nvim_win_set_cursor(0, {3, last - 1})
    ]])
    screen:input("<D-M-v>")
    h.wait(screen, function()
      return screen:exec("return vim.bo.filetype == 'snacks_input' and vim.fn.mode() == 'i'")
    end, "variable name prompt did not open")
    screen:input(typed .. "<Esc>")
    h.wait(screen, function()
      return screen:exec("return vim.bo.filetype ~= 'snacks_input' and vim.fn.mode() == 'n'")
    end, "one Esc did not close the prompt at once (typed: '" .. typed .. "')", 400)
    lib.eq(source, lines(screen))
  end
  lib.eq(0, screen:exec("return #_G.variable_notes"))
  screen:close()
end)

lib.test(
  "introduce variable: a language without a table requests only variable extraction code actions",
  function()
    local source = { "<?php", "function demo() {", "    return calculate();", "}" }
    local screen = editor(source, "calculate()", "unused")
    screen:exec([[
    vim.bo.filetype = 'rust'
    vim.lsp.buf.code_action = function(opts)
      _G.extract_action = {
        kind = opts.context.only[1], apply = opts.apply,
        variable = opts.filter({title='Extract variable'}),
        constant = opts.filter({title='Extract to constant'}),
        method = opts.filter({title='Extract function'}),
      }
    end
  ]])
    extract(screen)
    lib.eq(
      { kind = "refactor.extract", apply = true, variable = true, constant = true, method = false },
      screen:exec("return _G.extract_action")
    )
    lib.eq(source, lines(screen))
    screen:close()
  end
)

-- The suggested name: from where the value goes (named argument, array key, property), else from
-- the value itself; numbered when the scope already has it; none for a plain value.
for _, case in ipairs({
  { "    $x = $request->getContent();", "$request->getContent()", "content" },
  { "    return new ApiLogDocument();", "new ApiLogDocument()", "apiLogDocument" },
  { "    return new \\App\\Mongo\\ApiLogDocument();", "new \\App\\Mongo\\ApiLogDocument()", "apiLogDocument" },
  { "    $x = $_SERVER['REQUEST_TIME_FLOAT'] * 1000;", "$_SERVER['REQUEST_TIME_FLOAT']", "requestTimeFloat" },
  { "    log(direction: ApiCallDirection::Incoming);", "ApiCallDirection::Incoming", "direction" },
  { "    return ['user_id' => compute()];", "compute()", "userId" },
  { "    $this->total = $a + $b;", "$a + $b", "total" },
  { "    return $this->serviceText();", "$this->serviceText()", "serviceText" },
  { "    return microtime(true);", "microtime(true)", "microtime" },
  { "    return $order->customer;", "$order->customer", "customer" },
  { "    return ApiCallDirection::INCOMING_CALL;", "ApiCallDirection::INCOMING_CALL", "incomingCall" },
  { "    return $request->getContent() . $content;", "$request->getContent()", "content2" },
  { "    return 1 + 2;", "1 + 2", vim.NIL },
}) do
  lib.test("introduce variable: suggests " .. tostring(case[3]) .. " for " .. case[2], function()
    local source = { "<?php", "function demo($request, $order) {", case[1], "}" }
    local screen = editor(source, case[2], nil)
    extract(screen)
    h.wait(screen, function()
      return screen:exec("return #_G.variable_prompts") == 1
    end, "the name prompt did not open")
    lib.eq(case[3] ~= vim.NIL and case[3] or nil, screen:exec("return _G.variable_prompts[1].default"))
    screen:close()
  end)
end

lib.test("introduce variable: an argument is named after its parameter (the inlay hint)", function()
  local source = { "<?php", "function demo() {", "    $x = new Extractor(['/api/a']);", "}" }
  local screen = editor(source, "['/api/a']", nil)
  screen:exec([[
    _G.hint_requests = 0
    vim.lsp.start({
      name = 'hint-test', root_dir = vim.fn.getcwd(),
      cmd = function(dispatchers)
        local closing, id = false, 0
        return {
          request = function(method, params, callback)
            id = id + 1
            local result
            if method == 'initialize' then
              result = { capabilities = { inlayHintProvider = true } }
            elseif method == 'textDocument/inlayHint' then
              _G.hint_requests = _G.hint_requests + 1
              result = {
                { position = { line = 2, character = 23 }, label = 'pathPrefixesWithoutShipmentRef:', kind = 2 },
                { position = { line = 2, character = 4 }, label = 'other:', kind = 2 },
              }
            end
            vim.schedule(function() callback(nil, result) end)
            return true, id
          end,
          notify = function() return true end,
          is_closing = function() return closing end,
          terminate = function() closing = true; dispatchers.on_exit(0, 0) end,
        }
      end,
    })
  ]])
  h.wait(screen, function()
    return screen:exec("return #vim.lsp.get_clients({ bufnr = 0, name = 'hint-test' }) == 1 and vim.lsp.get_clients({ bufnr = 0, name = 'hint-test' })[1].initialized == true")
  end, "the language server did not attach")
  extract(screen)
  h.wait(screen, function()
    return screen:exec("return #_G.variable_prompts") == 1
  end, "the name prompt did not open")
  lib.eq("pathPrefixesWithoutShipmentRef", screen:exec("return _G.variable_prompts[1].default"))
  screen:close()
end)

lib.test("introduce variable: the suggestion is selected, Enter takes it, typing replaces it", function()
  for _, case in ipairs({
    { "<CR>", "content" },
    { "body<CR>", "body" },
    { "<BS>x<CR>", "x" },
    { "<End>Type<CR>", "contentType" },
    { "paste", "pasted" },
  }) do
    local source = { "<?php", "function demo($request) {", "    return $request->getContent();", "}" }
    local screen = editor(source, "$request->getContent()", "unused")
    screen:exec("vim.ui.input = _G.original_variable_input")
    screen:input("<D-M-v>")
    h.wait(screen, function()
      return screen:exec([[
        return vim.bo.filetype == 'snacks_input' and vim.fn.mode() == 'i'
          and #vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace('input-default-selection'), 0, -1, {}) == 1
      ]])
    end, "the suggested name is not shown selected")
    lib.eq({ "content" }, screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"))
    if case[1] == "paste" then
      screen:exec("vim.paste({ 'pasted' }, -1)")
      screen:input("<CR>")
    else
      screen:input(case[1])
    end
    h.wait(screen, function()
      return vim.deep_equal({
        "<?php",
        "function demo($request) {",
        "    $" .. case[2] .. " = $request->getContent();",
        "    return $" .. case[2] .. ";",
        "}",
      }, lines(screen))
    end, "keys " .. case[1] .. " did not name the variable $" .. case[2])
    screen:close()
  end
end)
