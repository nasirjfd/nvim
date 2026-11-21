-- Introduce Variable (Cmd+Option+V on a selection), the same in every language with a table in
-- languages.lua (PHP, TypeScript/JavaScript, Go, Lua, Python): the selected value goes into a new
-- variable declared above the statement, and the selection becomes a reference to it. The name is
-- suggested (names.lua) and shown selected. Selections that would change what runs, or when, are
-- refused. Other languages ask the language server for its "extract variable" code action.
local M = {}
local api = vim.api
local languages = require("core.introduce-variable.languages")

local function warn(message)
  vim.notify(message, vim.log.levels.WARN, { title = "Introduce Variable" })
end

local function advance(row, col, text)
  local lines = vim.split(text, "\n", { plain = true })
  return row + #lines - 1, (#lines == 1 and col or 0) + #lines[#lines]
end

local function selection()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" then
    return nil, "Select one continuous expression first"
  end
  local first, last = vim.fn.getpos("v"), vim.fn.getpos(".")
  local segments = vim.fn.getregionpos(first, last, { type = mode, eol = true })
  local text = table.concat(vim.fn.getregion(first, last, { type = mode }), "\n")
  local leading = text:match("^%s*")
  local expression = text:sub(#leading + 1):gsub("%s+$", ""):gsub(";$", ""):gsub("%s+$", "")
  if expression == "" then
    return nil, "Select an expression, not empty space"
  end
  local start = segments[1][1]
  local sr, sc = advance(start[2] - 1, start[3] - 1, leading)
  local er, ec = advance(sr, sc, expression)
  return { sr, sc, er, ec, text = expression }
end

local function same_range(node, range)
  local sr, sc, er, ec = node:range()
  return sr == range[1] and sc == range[2] and er == range[3] and ec == range[4]
end

local function contains(node, types)
  if types[node:type()] then
    return true
  end
  for child in node:iter_children() do
    if child:named() and contains(child, types) then
      return true
    end
  end
  return false
end

-- Names, keys and targets are not values: `x` in `const x = 1`, `total` in `obj.total`.
local NOT_VALUE_FIELDS = {
  name = true,
  key = true,
  property = true,
  field = true,
  attribute = true,
  pattern = true,
  label = true,
  type = true,
  parameters = true,
  constructor = true,
  method = true,
}

local function field_in_parent(node)
  local parent = node:parent()
  if not parent then
    return nil
  end
  for child, name in parent:iter_children() do
    if child == node then
      return name
    end
  end
end

-- The variables the selection itself assigns (`$a = 1`, `i++`): reading one of them earlier in
-- the statement would see a different value once the selection runs first.
local function assigned_names(node, lang, buf, out)
  out = out or {}
  local target = lang.targets[node:type()]
  local left = target and target(node)
  local function collect(n)
    if lang.variables[n:type()] then
      out[vim.treesitter.get_node_text(n, buf)] = true
    end
    for child in n:iter_children() do
      if child:named() then
        collect(child)
      end
    end
  end
  if left then
    collect(left)
  end
  if node:type() == "update_expression" then
    collect(node)
  end
  for child in node:iter_children() do
    if child:named() then
      assigned_names(child, lang, buf, out)
    end
  end
  return out
end

local function reads(node, lang, buf, names)
  if lang.variables[node:type()] and names[vim.treesitter.get_node_text(node, buf)] then
    return true
  end
  for child in node:iter_children() do
    if child:named() and reads(child, lang, buf, names) then
      return true
    end
  end
  return false
end

-- Identifiers that are not variables: `b` in `a.b`, keys, keyword-argument names.
local NOT_VARIABLE_FIELDS = { property = true, field = true, attribute = true, key = true, method = true, label = true }
local NAMED_KEYS = { keyword_argument = true, field = true, pair = true }

-- The variable names used or declared in a scope (from the tree, so `timeout=` or `obj.total` do
-- not count). A language without its own `exists` (text-based, PHP's $names) uses this.
local function variable_names(scope, lang, buf)
  local names = {}
  local function walk(node)
    if lang.variables[node:type()] then
      local name, parent = field_in_parent(node), node:parent()
      if not NOT_VARIABLE_FIELDS[name or ""] and not (name == "name" and parent and NAMED_KEYS[parent:type()]) then
        names[vim.treesitter.get_node_text(node, buf)] = true
      end
    end
    for child in node:iter_children() do
      if child:named() then
        walk(child)
      end
    end
  end
  walk(scope)
  return names
end

local function is_lazy(lang, parent)
  local kind = parent:type()
  if lang.lazy[kind] then
    return true
  end
  for _, prefix in ipairs(lang.lazy_prefixes or {}) do
    if kind:find(prefix) then
      return true
    end
  end
  if lang.lazy_binary[kind] then
    for token in parent:iter_children() do
      if lang.lazy_operators[token:type()] then
        return true
      end
    end
  end
  if lang.lazy_children then
    for child in parent:iter_children() do
      if lang.lazy_children[child:type()] then
        return true
      end
    end
  end
  return false
end

local function plan_for(buf, lang_name, lang, range)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, lang_name)
  if not ok or not parser then
    return nil, "The " .. lang.name .. " Tree-sitter parser is needed to introduce a variable"
  end
  local root = parser:parse()[1]:root()
  local node = root:named_descendant_for_range(range[1], range[2], range[3], range[4])
  while node and not (same_range(node, range) and lang.values[node:type()]) do
    node = node:parent()
  end
  if not node or node:has_error() or NOT_VALUE_FIELDS[field_in_parent(node) or ""] then
    return nil, "Select a complete " .. lang.name .. " expression (not part of a name or statement)"
  end
  local assigned = assigned_names(node, lang, buf)
  -- `a?.b` taken out of `a?.b.c()` would no longer stop the rest of the chain when `a` is missing.
  if lang.lazy_children and lang.chain_fields and lang.chain_fields[field_in_parent(node) or ""] then
    for part in node:iter_children() do
      if lang.lazy_children[part:type()] then
        return nil, "This selection cannot be moved without changing when it is evaluated"
      end
    end
  end
  local statement, child = node, node
  while statement:parent() do
    local parent = statement:parent()
    local kind = parent:type()
    if lang.blocks[kind] then
      break
    end
    -- Hoisting only one branch of a lazy expression would evaluate it unconditionally.
    local lazy = is_lazy(lang, parent)
    local target = lang.targets[kind]
    local left = target and target(parent)
    if left then
      local ls, lc, le, lend = left:range()
      if
        range[1] >= ls
        and range[3] <= le
        and (range[1] ~= ls or range[2] >= lc)
        and (range[3] ~= le or range[4] <= lend)
      then
        return nil, "Select a value, not an assignment target"
      end
    end
    for earlier in parent:iter_children() do
      local _, _, end_row, end_col = earlier:range()
      local before = end_row < range[1] or (end_row == range[1] and end_col <= range[2])
      -- A plain variable being assigned is written after the value is computed.
      local assignment_target = left
        and same_range(earlier, { left:range() })
        and lang.variables[left:type()]
      if
        earlier:named()
        and before
        and not assignment_target
        and (contains(earlier, lang.effects) or (next(assigned) and reads(earlier, lang, buf, assigned)))
      then
        return nil, "Extracting this selection would change the order of evaluation"
      end
    end
    if lazy or lang.callables[kind] then
      return nil, "This selection cannot be moved without changing when it is evaluated"
    end
    child, statement = statement, parent
  end
  if not lang.statements[statement:type()] then
    return nil, "Select an expression inside a statement body, not a loop or declaration header"
  end
  local sr, sc, er, ec = statement:range()
  local first_line = api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1]
  local indent = first_line:sub(1, sc)
  if indent:find("%S") then
    return nil, "Put the containing statement on its own line before extracting a variable"
  end
  local scope = statement
  while scope:parent() and not lang.callables[scope:type()] do
    scope = scope:parent()
  end
  local terminator = lang.terminator
  if type(terminator) == "function" then
    terminator = terminator(vim.treesitter.get_node_text(statement, buf))
  end
  return {
    range = range,
    row = sr,
    last = er + (ec > 0 and 1 or 0),
    indent = indent,
    statement_end = ec,
    scope = vim.treesitter.get_node_text(scope, buf),
    names = variable_names(scope, lang, buf),
    standalone = lang.standalone[statement:type()] ~= nil and (child == node or statement == node),
    terminator = terminator,
    node = node,
  }
end

local function exists(lang, plan, name)
  if lang.exists then
    return lang.exists(plan.scope, name)
  end
  return plan.names[name] == true
end

-- ── Name suggestion (like JetBrains) ─────────────────────────────────────────────────────────────
-- From where the value goes first (the parameter it is passed to, a named argument, a key, a
-- property it is assigned to), else from the value itself (getContent() -> content,
-- new ApiLogDocument() -> apiLogDocument, $_SERVER['REQUEST_TIME'] -> requestTime).

local function valid(lang, name)
  if not name or name == "" then
    return nil
  end
  local pattern = lang.identifier or "^[%a_][%w_]*$"
  if not name:match(pattern) or lang.reserved[name] then
    return nil
  end
  return name
end

function M.suggest(buf, plan, lang)
  local function value(node)
    return lang.value(node, buf, lang.case, value)
  end
  local name = valid(lang, lang.context(plan.node, buf, lang.case)) or valid(lang, value(plan.node))
  if not name then
    return nil
  end
  local unique, n = name, 1
  while exists(lang, plan, unique) do
    n = n + 1
    unique = name .. n
  end
  return unique
end

-- The suggestion is shown selected: the first typed character replaces it, Backspace clears it,
-- moving the cursor keeps it (like a selected text field).
-- The suggestion is shown selected, like a selected text field: the first key decides. A
-- character or a paste replaces it, Backspace / Ctrl+W / Ctrl+U clear it, anything else (Enter,
-- arrows, Home/End) keeps it as text. Handled in vim.on_key, before the key runs, so keys typed
-- faster than the screen updates (a paste and Enter at once) are still in order.
local CLEAR = { [vim.keycode("<BS>")] = true, [vim.keycode("<C-w>")] = true, [vim.keycode("<C-u>")] = true }
local function select_default(default)
  local ns = api.nvim_create_namespace("introduce-variable-default")
  -- The prompt window opens a moment after vim.ui.input returns.
  vim.schedule(function()
    local buf = api.nvim_get_current_buf()
    if vim.bo[buf].filetype ~= "snacks_input" or api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= default then
      return
    end
    api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = #default, hl_group = "Visual" })
    local listener, paste
    local active = true -- turned off at the first key: done() itself runs after the key
    local function done()
      active = false
      vim.on_key(nil, listener)
      if paste and vim.paste == paste.wrapper then
        vim.paste = paste.original
      end
      paste = nil
      if api.nvim_buf_is_valid(buf) then
        api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      end
    end
    listener = vim.on_key(function(key, typed)
      if not active then
        return
      end
      typed = typed ~= "" and typed or key
      if not api.nvim_buf_is_valid(buf) or api.nvim_get_current_buf() ~= buf then
        active = false
        return vim.schedule(done)
      end
      if vim.fn.mode() ~= "i" then
        return
      end
      local clear = CLEAR[typed]
      local char = not clear and #typed >= 1 and typed:byte(1) >= 32 and typed:byte(1) ~= 0x80
      if
        (clear or char)
        and api.nvim_buf_get_lines(buf, 0, 1, false)[1] == default
        and api.nvim_win_get_cursor(0)[2] == #default
      then
        active = false
        api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
        api.nvim_win_set_cursor(0, { 1, 0 })
        vim.schedule(done)
        return clear and "" or nil -- the clearing key itself is spent
      end
      active = false
      vim.schedule(done)
    end, api.nvim_create_namespace("introduce-variable-key"))
    -- A terminal paste (Cmd+V) does not pass through on_key: it replaces the suggestion as well.
    paste = { original = vim.paste }
    paste.wrapper = function(lines, phase)
      local original = paste and paste.original or vim.paste
      if
        active
        and api.nvim_get_current_buf() == buf
        and api.nvim_buf_get_lines(buf, 0, 1, false)[1] == default
        and (phase == -1 or phase == 1)
      then
        api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
        api.nvim_win_set_cursor(0, { 1, 0 })
      end
      done()
      return original(lines, phase)
    end
    vim.paste = paste.wrapper
    api.nvim_create_autocmd("BufLeave", { buffer = buf, once = true, callback = done })
  end)
end

local function apply(buf, plan, lang, name)
  local r = plan.range
  local original = api.nvim_buf_get_lines(buf, plan.row, plan.last, false)
  local expression = vim.split(r.text, "\n", { plain = true })
  local reference = lang.reference(name)
  -- Preserve the selection verbatim: reindenting continuation lines can change
  -- the value of a multiline string or heredoc embedded in the expression.
  expression[1] = plan.indent .. lang.declare(name) .. expression[1]
  expression[#expression] = expression[#expression] .. plan.terminator
  if plan.standalone then
    expression[#expression] = expression[#expression]
      .. original[#original]:sub(plan.statement_end + 1)
  else
    local first, last = r[1] - plan.row + 1, r[3] - plan.row + 1
    local replaced = original[first]:sub(1, r[2]) .. reference .. original[last]:sub(r[4] + 1)
    local statement = {}
    vim.list_extend(statement, vim.list_slice(original, 1, first - 1))
    statement[#statement + 1] = replaced
    vim.list_extend(statement, vim.list_slice(original, last + 1))
    vim.list_extend(expression, statement)
  end
  api.nvim_buf_set_lines(buf, plan.row, plan.last, false, expression)
  api.nvim_win_set_cursor(0, { plan.row + 1, #plan.indent + 1 })
end

function M.extract()
  local buf = api.nvim_get_current_buf()
  if not vim.bo[buf].modifiable or vim.bo[buf].readonly then
    return warn("This buffer is not editable")
  end
  local range, err = selection()
  if not range then
    return warn(err)
  end
  local lang_name = vim.treesitter.language.get_lang(vim.bo[buf].filetype) or vim.bo[buf].filetype
  local lang = languages[lang_name]
  if not lang then
    return vim.lsp.buf.code_action({
      context = { only = { "refactor.extract" }, diagnostics = {} },
      filter = function(action)
        local title = action.title:lower()
        return title:find("variable", 1, true) ~= nil or title:find("constant", 1, true) ~= nil
      end,
      apply = true,
    })
  end
  local plan
  plan, err = plan_for(buf, lang_name, lang, range)
  if not plan then
    return warn(err)
  end
  local tick = api.nvim_buf_get_changedtick(buf)
  local win = api.nvim_get_current_win()
  vim.cmd("normal! \27")
  -- The name starts with a suggestion (selected) or empty. Enter on an empty name says so and asks
  -- again (empty); Esc (nil) cancels.
  local named
  local suggestion = M.suggest(buf, plan, lang)
  local function ask(default)
    vim.ui.input({ prompt = "Variable name: ", default = default }, function(name)
      if not name then
        return
      end
      name = vim.trim(name)
      if lang.normalize then
        name = lang.normalize(name)
      end
      if name == "" then
        vim.notify("Enter a variable name", vim.log.levels.ERROR, { title = "Introduce Variable" })
        return vim.schedule(function()
          ask()
        end)
      end
      return named(name)
    end)
  end
  function named(name)
    if not name:match(lang.identifier or "^[%a_][%w_]*$") or lang.reserved[name] then
      return warn(
        "Enter a new "
          .. lang.name
          .. " variable name"
          .. (lang.normalize and ", with or without $" or "")
      )
    end
    if exists(lang, plan, name) then
      return warn(lang.reference(name) .. " already exists in this scope; choose a different name")
    end
    if
      not api.nvim_buf_is_valid(buf)
      or not api.nvim_win_is_valid(win)
      or api.nvim_get_current_buf() ~= buf
      or api.nvim_get_current_win() ~= win
      or api.nvim_buf_get_changedtick(buf) ~= tick
    then
      return warn("The buffer changed while naming the variable; select the expression again")
    end
    apply(buf, plan, lang, name)
  end
  ask(suggestion)
  if suggestion then
    select_default(suggestion)
  end
end

return M
