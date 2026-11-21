local M = {}
local api = vim.api

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

local VALUES = {
  variable_name = true,
  integer = true,
  float = true,
  boolean = true,
  null = true,
  string = true,
  encapsed_string = true,
  heredoc = true,
  nowdoc = true,
  array_creation_expression = true,
  function_call_expression = true,
  member_call_expression = true,
  scoped_call_expression = true,
  member_access_expression = true,
  scoped_property_access_expression = true,
  class_constant_access_expression = true,
  subscript_expression = true,
  binary_expression = true,
  conditional_expression = true,
  parenthesized_expression = true,
  unary_op_expression = true,
  cast_expression = true,
  object_creation_expression = true,
  clone_expression = true,
  match_expression = true,
}
local STATEMENTS = { expression_statement = true, return_statement = true, echo_statement = true }
local CALLABLES = {
  function_definition = true,
  method_declaration = true,
  anonymous_function_creation_expression = true,
  arrow_function = true,
}

local function same_range(node, range)
  local sr, sc, er, ec = node:range()
  return sr == range[1] and sc == range[2] and er == range[3] and ec == range[4]
end

local EFFECTS = {
  function_call_expression = true,
  member_call_expression = true,
  scoped_call_expression = true,
  object_creation_expression = true,
  update_expression = true,
  assignment_expression = true,
  augmented_assignment_expression = true,
  reference_assignment_expression = true,
}

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

local function php_plan(buf, range)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "php")
  if not ok then
    return nil, "The PHP Tree-sitter parser is needed to introduce a variable"
  end
  local root = parser:parse()[1]:root()
  local node = root:named_descendant_for_range(range[1], range[2], range[3], range[4])
  while node and not (same_range(node, range) and VALUES[node:type()]) do
    node = node:parent()
  end
  if not node or node:has_error() then
    return nil, "Select a complete PHP expression (not part of a name or statement)"
  end
  local has_effect = contains(node, EFFECTS)
  local statement, child = node, node
  while statement:parent() do
    local parent = statement:parent()
    local kind = parent:type()
    if kind == "compound_statement" or kind == "program" then
      break
    end
    -- Hoisting only one branch of a lazy expression would evaluate it unconditionally.
    local lazy = kind == "conditional_expression"
      or kind == "arrow_function"
      or kind:find("^nullsafe_")
      or kind:find("^match_")
    if kind == "binary_expression" then
      for token in parent:iter_children() do
        local operator = token:type()
        lazy = lazy
          or operator == "&&"
          or operator == "||"
          or operator == "??"
          or operator == "and"
          or operator == "or"
      end
    end
    local left = parent:field("left")[1]
    if kind:find("assignment_expression$") and left then
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
      local assignment_target = kind:find("assignment_expression$")
        and left
        and same_range(earlier, { left:range() })
        and left:type() == "variable_name"
      if
        earlier:named()
        and before
        and not assignment_target
        and (
          contains(earlier, EFFECTS) or (has_effect and contains(earlier, { variable_name = true }))
        )
      then
        return nil, "Extracting this selection would change the order of evaluation"
      end
    end
    if lazy or CALLABLES[kind] then
      return nil, "This selection cannot be moved without changing when it is evaluated"
    end
    child, statement = statement, parent
  end
  if not STATEMENTS[statement:type()] then
    return nil, "Select an expression inside a statement body, not a loop or declaration header"
  end
  local sr, sc, er, ec = statement:range()
  local first_line = api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1]
  local indent = first_line:sub(1, sc)
  if indent:find("%S") then
    return nil, "Put the containing statement on its own line before extracting a variable"
  end
  local scope = statement
  while scope:parent() and not CALLABLES[scope:type()] do
    scope = scope:parent()
  end
  return {
    range = range,
    row = sr,
    last = er + (ec > 0 and 1 or 0),
    indent = indent,
    statement_end = ec,
    scope = vim.treesitter.get_node_text(scope, buf),
    standalone = statement:type() == "expression_statement" and child == node,
    node = node,
  }
end

local function exists(scope, name)
  return scope:find("%$" .. name .. "%f[^%w_]") ~= nil
end

-- ── Name suggestion (like JetBrains) ─────────────────────────────────────────────────────────────
-- From where the value goes first (the parameter it is passed to, a named argument, an array key, a
-- property it is assigned to), else from the value itself (getContent() -> content,
-- new ApiLogDocument() -> apiLogDocument, $_SERVER['REQUEST_TIME'] -> requestTime).

local function camel(word)
  if not word or word == "" then
    return nil
  end
  if word:find("_") or word:upper() == word then
    -- SNAKE_CASE, snake_case, UPPER -> lowerCamel
    local out = word:lower():gsub("_+(%w)", string.upper):gsub("^_+", "")
    return out
  end
  return (word:gsub("^%u+", function(caps)
    -- ApiLog -> apiLog, URLPath -> urlPath
    if #caps == 1 or #caps == #word then
      return caps:lower()
    end
    return caps:sub(1, -2):lower() .. caps:sub(-1)
  end))
end

local RESERVED_NAMES -- set below, after RESERVED
local function valid(name)
  return name and name:match("^[%a_][%w_]*$") and not RESERVED_NAMES[name] and name or nil
end

local function text_of(node, buf)
  return node and vim.treesitter.get_node_text(node, buf) or nil
end

local function last_named(node, types)
  local found
  for child in node:iter_children() do
    if child:named() and (not types or types[child:type()]) then
      found = child
    end
  end
  return found
end

-- The parameter name the language server shows as an inlay hint at the argument's start.
local function parameter_hint(buf, row, col)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, method = "textDocument/inlayHint" })) do
    local params = {
      textDocument = vim.lsp.util.make_text_document_params(buf),
      range = { start = { line = row, character = 0 }, ["end"] = { line = row + 1, character = 0 } },
    }
    local response = client:request_sync("textDocument/inlayHint", params, 800, buf)
    for _, hint in ipairs(response and response.result or {}) do
      local label = hint.label
      if type(label) == "table" then
        label = table.concat(vim.tbl_map(function(part)
          return part.value
        end, label))
      end
      -- Positions are UTF-16; the hint sits at the argument's first character.
      local ok, byte = pcall(vim.lsp.util._get_line_byte_from_position, buf, hint.position, client.offset_encoding)
      if hint.position.line == row and (ok and byte or hint.position.character) == col then
        local name = vim.trim(label):gsub(":$", ""):gsub("^%$", ""):gsub("^%.%.%.", "")
        if valid(name) then
          return name
        end
      end
    end
  end
end

local function from_context(node, buf)
  local parent = node:parent()
  if not parent then
    return nil
  end
  local kind = parent:type()
  if kind == "argument" then
    local name = parent:field("name")[1]
    if name then
      return text_of(name, buf)
    end
    local row, col = parent:range()
    return parameter_hint(buf, row, col)
  elseif kind == "array_element_initializer" then
    local key = parent:named_child(0)
    if key and key ~= node and parent:named_child_count() == 2 then
      local word = text_of(key, buf):match("^['\"]([%w_]+)['\"]$")
      return camel(word)
    end
  elseif kind == "assignment_expression" then
    local left = parent:field("left")[1]
    if left and left ~= node and (left:type() == "member_access_expression" or left:type() == "scoped_property_access_expression") then
      local name = left:field("name")[1] or last_named(left)
      return text_of(name, buf) and text_of(name, buf):gsub("^%$", "")
    end
  end
end

local function from_value(node, buf)
  local kind = node:type()
  if kind == "parenthesized_expression" or kind == "cast_expression" or kind == "clone_expression" then
    local inner = last_named(node)
    return inner and from_value(inner, buf)
  elseif kind == "member_call_expression" or kind == "scoped_call_expression" or kind == "nullsafe_member_call_expression" then
    local name = text_of(node:field("name")[1], buf)
    if not name then
      return nil
    end
    local stripped = name:match("^get(%u.*)$")
    return camel(stripped or name)
  elseif kind == "function_call_expression" then
    local fn = text_of(node:field("function")[1], buf)
    return fn and camel(fn:match("([%w_]+)$"))
  elseif kind == "object_creation_expression" then
    local class = last_named(node, { name = true, qualified_name = true })
    local text = class and text_of(class, buf)
    return text and camel(text:match("([%w_]+)$"))
  elseif kind == "member_access_expression" or kind == "nullsafe_member_access_expression" then
    return text_of(node:field("name")[1], buf)
  elseif kind == "scoped_property_access_expression" then
    local name = text_of(node:field("name")[1], buf)
    return name and name:gsub("^%$", "")
  elseif kind == "class_constant_access_expression" then
    local name = text_of(last_named(node), buf)
    return camel(name)
  elseif kind == "subscript_expression" then
    local index = last_named(node)
    local word = index and text_of(index, buf):match("^['\"]([%w_]+)['\"]$")
    return camel(word)
  end
end

function M.suggest(buf, plan)
  local name = valid(from_context(plan.node, buf)) or valid(from_value(plan.node, buf))
  if not name then
    return nil
  end
  local unique, n = name, 1
  while exists(plan.scope, unique) do
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

local RESERVED = {
  this = true,
  GLOBALS = true,
  _SERVER = true,
  _GET = true,
  _POST = true,
  _FILES = true,
  _COOKIE = true,
  _SESSION = true,
  _REQUEST = true,
  _ENV = true,
}

RESERVED_NAMES = RESERVED

local function apply(buf, plan, name)
  local r = plan.range
  local original = api.nvim_buf_get_lines(buf, plan.row, plan.last, false)
  local expression = vim.split(r.text, "\n", { plain = true })
  -- Preserve the selection verbatim: reindenting continuation lines can change
  -- the value of a multiline string or heredoc embedded in the expression.
  expression[1] = plan.indent .. "$" .. name .. " = " .. expression[1]
  expression[#expression] = expression[#expression] .. ";"
  if plan.standalone then
    expression[#expression] = expression[#expression]
      .. original[#original]:sub(plan.statement_end + 1)
  else
    local first, last = r[1] - plan.row + 1, r[3] - plan.row + 1
    local replaced = original[first]:sub(1, r[2]) .. "$" .. name .. original[last]:sub(r[4] + 1)
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
  if vim.bo[buf].filetype ~= "php" then
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
  plan, err = php_plan(buf, range)
  if not plan then
    return warn(err)
  end
  local tick = api.nvim_buf_get_changedtick(buf)
  local win = api.nvim_get_current_win()
  vim.cmd("normal! \27")
  -- The name starts with a suggestion (selected) or empty. Enter on an empty name says so and asks
  -- again (empty); Esc (nil) cancels.
  local named
  local suggestion = M.suggest(buf, plan)
  local function ask(default)
    vim.ui.input({ prompt = "Variable name: ", default = default }, function(name)
      if not name then
        return
      end
      name = vim.trim(name):gsub("^%$", "")
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
    if not name:match("^[%a_][%w_]*$") or RESERVED[name] then
      return warn("Enter a new PHP variable name, with or without $")
    end
    if exists(plan.scope, name) then
      return warn("$" .. name .. " already exists in this scope; choose a different name")
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
    apply(buf, plan, name)
  end
  ask(suggestion)
  if suggestion then
    select_default(suggestion)
  end
end

return M
