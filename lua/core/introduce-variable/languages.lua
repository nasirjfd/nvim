-- Per-language tables for the Introduce Variable engine (init.lua). Each table says, in that
-- language's Tree-sitter node names:
--   values      which nodes are values that can be put in a variable
--   statements  the statements a variable can be declared above
--   blocks      the nodes that hold a list of statements (a function body, the file)
--   standalone  statements that are only the value (`call();`): the statement becomes the declaration
--   callables   function bodies: the scope of a name and a boundary nothing is moved out of
--   effects     nodes with side effects (calls, assignments): the evaluation order must not change
--   variables   the variable reference node
--   lazy        nodes evaluated only sometimes (`a ? b : c`), lazy_operators for binary nodes
--               (`&&`, `or`), lazy_children a child making its parent lazy (`?.`)
--   targets     assignment nodes -> the part that is written (a value selected there is refused)
--   declare     the declaration line, reference the name in the code, case of suggested names
--   exists      (PHP) whether a name is taken, from the text; others use the tree's variables
--   context     a name from where the value goes (a key, a named argument, a property)
--   value       a name from the value itself (a call, a member, a constructor)
local util = require("core.introduce-variable.names")

local function set(list)
  local out = {}
  for _, item in ipairs(list) do
    out[item] = true
  end
  return out
end

local function field(node, name)
  return node and node:field(name)[1]
end

local function left_field(node)
  return field(node, "left")
end

local M = {}

-- ── PHP ───────────────────────────────────────────────────────────────────────────────────────────
M.php = {
  name = "PHP",
  values = set({
    "variable_name", "integer", "float", "boolean", "null", "string", "encapsed_string", "heredoc",
    "nowdoc", "array_creation_expression", "function_call_expression", "member_call_expression",
    "scoped_call_expression", "member_access_expression", "scoped_property_access_expression",
    "class_constant_access_expression", "subscript_expression", "binary_expression",
    "conditional_expression", "parenthesized_expression", "unary_op_expression", "cast_expression",
    "object_creation_expression", "clone_expression", "match_expression",
  }),
  statements = set({ "expression_statement", "return_statement", "echo_statement" }),
  blocks = set({ "compound_statement", "program" }),
  standalone = set({ "expression_statement" }),
  callables = set({
    "function_definition", "method_declaration", "anonymous_function_creation_expression",
    "arrow_function",
  }),
  effects = set({
    "function_call_expression", "member_call_expression", "scoped_call_expression",
    "object_creation_expression", "update_expression", "assignment_expression",
    "augmented_assignment_expression", "reference_assignment_expression",
  }),
  variables = set({ "variable_name" }),
  lazy = set({ "conditional_expression", "arrow_function" }),
  lazy_prefixes = { "^nullsafe_", "^match_" },
  lazy_binary = set({ "binary_expression" }),
  lazy_operators = set({ "&&", "||", "??", "and", "or" }),
  targets = {
    assignment_expression = left_field,
    augmented_assignment_expression = left_field,
    reference_assignment_expression = left_field,
  },
  arguments = set({ "argument" }),
  reserved = set({
    "this", "GLOBALS", "_SERVER", "_GET", "_POST", "_FILES", "_COOKIE", "_SESSION", "_REQUEST", "_ENV",
  }),
  case = "camel",
  terminator = ";",
  declare = function(name)
    return "$" .. name .. " = "
  end,
  reference = function(name)
    return "$" .. name
  end,
  exists = function(scope, name)
    return scope:find("%$" .. name .. "%f[^%w_]") ~= nil
  end,
  normalize = function(name)
    return (name:gsub("^%$", ""))
  end,
  context = function(node, buf, case)
    local parent = node:parent()
    local kind = parent and parent:type()
    if kind == "argument" then
      local name = field(parent, "name")
      if name then
        return util.text(name, buf)
      end
      local row, col = parent:range()
      return util.parameter_hint(buf, row, col)
    elseif kind == "array_element_initializer" then
      local key = parent:named_child(0)
      if key and key ~= node and parent:named_child_count() == 2 then
        return util.cased(util.string_word(util.text(key, buf)), case)
      end
    elseif kind == "assignment_expression" then
      local left = field(parent, "left")
      if
        left
        and left ~= node
        and (
          left:type() == "member_access_expression"
          or left:type() == "scoped_property_access_expression"
        )
      then
        local name = util.text(field(left, "name") or util.last_named(left), buf)
        return name and (name:gsub("^%$", ""))
      end
    end
  end,
  value = function(node, buf, case, value)
    local kind = node:type()
    if
      kind == "parenthesized_expression"
      or kind == "cast_expression"
      or kind == "clone_expression"
    then
      local inner = util.last_named(node)
      return inner and value(inner)
    elseif
      kind == "member_call_expression"
      or kind == "scoped_call_expression"
      or kind == "nullsafe_member_call_expression"
    then
      return util.call_name(util.text(field(node, "name"), buf), case)
    elseif kind == "function_call_expression" then
      return util.call_name(util.text(field(node, "function"), buf), case)
    elseif kind == "object_creation_expression" then
      local class = util.last_named(node, set({ "name", "qualified_name" }))
      return util.cased(util.last_word(util.text(class, buf)), case)
    elseif kind == "member_access_expression" or kind == "nullsafe_member_access_expression" then
      return util.text(field(node, "name"), buf)
    elseif kind == "scoped_property_access_expression" then
      local name = util.text(field(node, "name"), buf)
      return name and (name:gsub("^%$", ""))
    elseif kind == "class_constant_access_expression" then
      return util.cased(util.text(util.last_named(node), buf), case)
    elseif kind == "subscript_expression" then
      local index = util.last_named(node)
      return util.cased(util.string_word(util.text(index, buf)), case)
    end
  end,
}

-- ── TypeScript / JavaScript ───────────────────────────────────────────────────────────────────────
M.typescript = {
  name = "TypeScript",
  values = set({
    "identifier", "number", "string", "template_string", "true", "false", "null", "undefined",
    "regex", "array", "object", "call_expression", "member_expression", "subscript_expression",
    "binary_expression", "ternary_expression", "parenthesized_expression", "unary_expression",
    "new_expression", "await_expression", "as_expression", "satisfies_expression",
    "non_null_expression", "arrow_function", "function_expression", "this",
  }),
  statements = set({
    "expression_statement", "return_statement", "lexical_declaration", "variable_declaration",
    "throw_statement",
  }),
  blocks = set({ "statement_block", "program" }),
  standalone = set({ "expression_statement" }),
  callables = set({
    "function_declaration", "function_expression", "arrow_function", "method_definition",
    "generator_function_declaration", "generator_function", "function",
  }),
  effects = set({
    "call_expression", "new_expression", "assignment_expression", "augmented_assignment_expression",
    "update_expression", "await_expression", "yield_expression", "variable_declarator",
  }),
  variables = set({ "identifier", "this" }),
  lazy = set({ "ternary_expression" }),
  lazy_binary = set({ "binary_expression" }),
  lazy_operators = set({ "&&", "||", "??" }),
  lazy_children = set({ "optional_chain" }),
  targets = {
    assignment_expression = left_field,
    augmented_assignment_expression = left_field,
  },
  arguments = set({ "arguments" }),
  reserved = set({
    "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do",
    "else", "enum", "export", "extends", "false", "finally", "for", "function", "if", "import", "in",
    "instanceof", "new", "null", "return", "super", "switch", "this", "throw", "true", "try",
    "typeof", "var", "void", "while", "with", "let", "static", "yield", "await", "undefined",
  }),
  case = "camel",
  -- Follow the file: a semicolon only where the statement had one.
  terminator = function(statement_text)
    return statement_text:match(";%s*$") and ";" or ""
  end,
  declare = function(name)
    return "const " .. name .. " = "
  end,
  reference = function(name)
    return name
  end,
  identifier = "^[%a_$][%w_$]*$",
  chain_fields = set({ "object", "function" }),
  context = function(node, buf, case)
    local parent = node:parent()
    local kind = parent and parent:type()
    if kind == "arguments" then
      local row, col = node:range()
      return util.parameter_hint(buf, row, col)
    elseif kind == "pair" and field(parent, "value") == node then
      local key = field(parent, "key")
      local text = util.text(key, buf)
      return util.cased(util.string_word(text) or text, case)
    elseif kind == "assignment_expression" and field(parent, "right") == node then
      local left = field(parent, "left")
      if left and left:type() == "member_expression" then
        return util.text(field(left, "property"), buf)
      end
    end
  end,
  value = function(node, buf, case, value)
    local kind = node:type()
    if
      kind == "parenthesized_expression"
      or kind == "await_expression"
      or kind == "non_null_expression"
      or kind == "as_expression"
      or kind == "satisfies_expression"
    then
      local inner = node:named_child(0)
      return inner and value(inner)
    elseif kind == "call_expression" then
      return util.call_name(util.text(field(node, "function"), buf), case)
    elseif kind == "new_expression" then
      return util.cased(util.last_word(util.text(field(node, "constructor"), buf)), case)
    elseif kind == "member_expression" then
      return util.text(field(node, "property"), buf)
    elseif kind == "subscript_expression" then
      return util.cased(util.string_word(util.text(field(node, "index"), buf)), case)
    end
  end,
}
M.javascript = vim.tbl_extend("force", M.typescript, { name = "JavaScript" })
M.tsx = M.typescript

-- ── Go ────────────────────────────────────────────────────────────────────────────────────────────
M.go = {
  name = "Go",
  values = set({
    "identifier", "int_literal", "float_literal", "imaginary_literal", "rune_literal",
    "interpreted_string_literal", "raw_string_literal", "true", "false", "nil", "call_expression",
    "selector_expression", "index_expression", "slice_expression", "binary_expression",
    "unary_expression", "composite_literal", "func_literal", "parenthesized_expression",
    "type_assertion_expression", "type_conversion_expression",
  }),
  statements = set({
    "expression_statement", "return_statement", "assignment_statement", "short_var_declaration",
    "var_declaration", "send_statement", "inc_statement", "dec_statement",
  }),
  blocks = set({ "statement_list", "block" }),
  standalone = set({ "expression_statement" }),
  callables = set({ "function_declaration", "method_declaration", "func_literal" }),
  effects = set({ "call_expression", "assignment_statement", "short_var_declaration", "inc_statement", "dec_statement" }),
  variables = set({ "identifier" }),
  lazy = set({}),
  lazy_binary = set({ "binary_expression" }),
  lazy_operators = set({ "&&", "||" }),
  targets = {
    assignment_statement = left_field,
    short_var_declaration = left_field,
  },
  arguments = set({ "argument_list" }),
  reserved = set({
    "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for",
    "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select",
    "struct", "switch", "type", "var", "nil", "true", "false", "iota",
  }),
  case = "camel",
  terminator = "",
  declare = function(name)
    return name .. " := "
  end,
  reference = function(name)
    return name
  end,
  context = function(node, buf, case)
    local parent = node:parent()
    local kind = parent and parent:type()
    if kind == "argument_list" then
      local row, col = node:range()
      return util.parameter_hint(buf, row, col)
    elseif kind == "literal_element" then
      local element = parent:parent()
      if element and element:type() == "keyed_element" and field(element, "value") == parent then
        local key = util.text(field(element, "key"), buf)
        return util.cased(util.string_word(key) or key, case)
      end
    elseif kind == "expression_list" then
      local statement = parent:parent()
      if
        statement
        and statement:type() == "assignment_statement"
        and field(statement, "right") == parent
        and parent:named_child_count() == 1
      then
        local left = field(statement, "left")
        local target = left and left:named_child_count() == 1 and left:named_child(0)
        if target and target:type() == "selector_expression" then
          return util.cased(util.text(field(target, "field"), buf), case)
        end
      end
    end
  end,
  value = function(node, buf, case, value)
    local kind = node:type()
    if kind == "parenthesized_expression" then
      local inner = node:named_child(0)
      return inner and value(inner)
    elseif kind == "call_expression" then
      return util.call_name(util.text(field(node, "function"), buf), case)
    elseif kind == "composite_literal" then
      return util.cased(util.last_word(util.text(field(node, "type"), buf)), case)
    elseif kind == "selector_expression" then
      return util.cased(util.text(field(node, "field"), buf), case)
    elseif kind == "index_expression" then
      return util.cased(util.string_word(util.text(field(node, "index"), buf)), case)
    end
  end,
}

-- ── Lua ───────────────────────────────────────────────────────────────────────────────────────────
M.lua = {
  name = "Lua",
  values = set({
    "identifier", "number", "string", "true", "false", "nil", "function_call",
    "dot_index_expression", "bracket_index_expression", "binary_expression", "unary_expression",
    "parenthesized_expression", "table_constructor", "function_definition", "vararg_expression",
  }),
  statements = set({ "assignment_statement", "variable_declaration", "return_statement", "function_call" }),
  blocks = set({ "block", "chunk" }),
  -- A call on its own line is the statement itself.
  standalone = set({ "function_call" }),
  callables = set({ "function_declaration", "function_definition" }),
  effects = set({ "function_call", "assignment_statement", "variable_declaration" }),
  variables = set({ "identifier" }),
  lazy = set({}),
  lazy_binary = set({ "binary_expression" }),
  lazy_operators = set({ "and", "or" }),
  targets = {
    assignment_statement = function(node)
      return node:named_child(0) -- the variable_list
    end,
  },
  arguments = set({ "arguments" }),
  reserved = set({
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
  }),
  case = "snake",
  terminator = "",
  declare = function(name)
    return "local " .. name .. " = "
  end,
  reference = function(name)
    return name
  end,
  context = function(node, buf, case)
    local parent = node:parent()
    local kind = parent and parent:type()
    if kind == "arguments" then
      local row, col = node:range()
      return util.parameter_hint(buf, row, col)
    elseif kind == "field" and field(parent, "value") == node then
      local key = field(parent, "name")
      return key and util.cased(util.string_word(util.text(key, buf)) or util.text(key, buf), case)
    elseif kind == "expression_list" then
      local statement = parent:parent()
      local targets = statement and statement:type() == "assignment_statement" and statement:named_child(0)
      if targets and targets ~= parent and targets:named_child_count() == 1 and parent:named_child_count() == 1 then
        local target = targets:named_child(0)
        if target:type() == "dot_index_expression" then
          return util.cased(util.text(field(target, "field"), buf), case)
        end
      end
    end
  end,
  value = function(node, buf, case, value)
    local kind = node:type()
    if kind == "parenthesized_expression" then
      local inner = node:named_child(0)
      return inner and value(inner)
    elseif kind == "function_call" then
      return util.call_name(util.text(field(node, "name"), buf), case)
    elseif kind == "dot_index_expression" then
      return util.cased(util.text(field(node, "field"), buf), case)
    elseif kind == "bracket_index_expression" then
      return util.cased(util.string_word(util.text(field(node, "field"), buf)), case)
    end
  end,
}

-- ── Python ────────────────────────────────────────────────────────────────────────────────────────
local COMPREHENSIONS = {
  "list_comprehension", "set_comprehension", "dictionary_comprehension", "generator_expression",
}
M.python = {
  name = "Python",
  values = set({
    "identifier", "integer", "float", "string", "concatenated_string", "true", "false", "none",
    "call", "attribute", "subscript", "binary_operator", "boolean_operator", "comparison_operator",
    "not_operator", "unary_operator", "conditional_expression", "parenthesized_expression", "list",
    "dictionary", "set", "tuple", "lambda", "await", unpack(COMPREHENSIONS),
  }),
  statements = set({ "expression_statement", "return_statement", "raise_statement" }),
  blocks = set({ "block", "module" }),
  standalone = set({ "expression_statement" }),
  -- A comprehension runs its parts per item, like a function body.
  callables = set({ "function_definition", "lambda", unpack(COMPREHENSIONS) }),
  effects = set({ "call", "assignment", "augmented_assignment", "named_expression", "await", "yield" }),
  variables = set({ "identifier" }),
  lazy = set({ "conditional_expression" }),
  lazy_binary = set({ "boolean_operator" }),
  lazy_operators = set({ "and", "or" }),
  targets = {
    assignment = left_field,
    augmented_assignment = left_field,
  },
  arguments = set({ "argument_list" }),
  reserved = set({
    "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue",
    "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in",
    "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with",
    "yield", "self", "cls",
  }),
  case = "snake",
  terminator = "",
  declare = function(name)
    return name .. " = "
  end,
  reference = function(name)
    return name
  end,
  context = function(node, buf, case)
    local parent = node:parent()
    local kind = parent and parent:type()
    if kind == "argument_list" then
      local row, col = node:range()
      return util.parameter_hint(buf, row, col)
    elseif kind == "keyword_argument" and field(parent, "value") == node then
      return util.text(field(parent, "name"), buf)
    elseif kind == "pair" and field(parent, "value") == node then
      return util.cased(util.string_word(util.text(field(parent, "key"), buf)), case)
    elseif kind == "assignment" and field(parent, "right") == node then
      local left = field(parent, "left")
      if left and left:type() == "attribute" then
        return util.cased(util.text(field(left, "attribute"), buf), case)
      end
    end
  end,
  value = function(node, buf, case, value)
    local kind = node:type()
    if kind == "parenthesized_expression" or kind == "await" then
      local inner = node:named_child(0)
      return inner and value(inner)
    elseif kind == "call" then
      return util.call_name(util.text(field(node, "function"), buf), case)
    elseif kind == "attribute" then
      return util.cased(util.text(field(node, "attribute"), buf), case)
    elseif kind == "subscript" then
      return util.cased(util.string_word(util.text(field(node, "subscript"), buf)), case)
    end
  end,
}

return M
