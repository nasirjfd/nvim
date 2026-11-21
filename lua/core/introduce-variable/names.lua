-- Helpers for suggested variable names, shared by every language table.
local M = {}

function M.text(node, buf)
  return node and vim.treesitter.get_node_text(node, buf) or nil
end

function M.last_named(node, types)
  local found
  for child in node:iter_children() do
    if child:named() and (not types or types[child:type()]) then
      found = child
    end
  end
  return found
end

-- The last identifier of a dotted/qualified name: \App\Mongo\ApiLogDocument -> ApiLogDocument,
-- a.b.getContent -> getContent, Foo<Bar> -> Foo.
function M.last_word(text)
  if not text then
    return nil
  end
  text = text:gsub("%b<>", ""):gsub("%b[]", "")
  return text:match("([%a_][%w_]*)%s*$")
end

-- The word inside a string literal key: 'user_id' -> user_id, "REQUEST_TIME" -> REQUEST_TIME.
function M.string_word(text)
  return text and text:match("^[rbfu]*['\"`]([%a_][%w_]*)['\"`]$") or nil
end

local function camel(word)
  if word:find("_") or word:upper() == word then
    -- SNAKE_CASE, snake_case, UPPER -> lowerCamel
    return (word:lower():gsub("_+(%w)", string.upper):gsub("^_+", ""))
  end
  return (word:gsub("^%u+", function(caps)
    -- ApiLog -> apiLog, URLPath -> urlPath
    if #caps == 1 or #caps == #word then
      return caps:lower()
    end
    return caps:sub(1, -2):lower() .. caps:sub(-1)
  end))
end

local function snake(word)
  if word:upper() == word then
    return word:lower()
  end
  -- ApiLog -> api_log, URLPath -> url_path, getContent -> get_content
  word = word:gsub("(%u+)(%u%l)", "%1_%2"):gsub("(%l%d?)(%u)", "%1_%2")
  return (word:lower():gsub("^_+", ""))
end

function M.cased(word, case)
  if not word or word == "" then
    return nil
  end
  return case == "snake" and snake(word) or camel(word)
end

-- A call's name without its "get": getContent() -> content, get_user() -> user, GetID() -> id.
function M.call_name(callee, case)
  local name = M.last_word(callee)
  if not name then
    return nil
  end
  local stripped = name:match("^[gG]et(%u.*)$") or name:match("^get_(%a.*)$")
  return M.cased(stripped or name, case)
end

-- The parameter name the language server shows as an inlay hint at the argument's start.
function M.parameter_hint(buf, row, col)
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
      local ok, byte = pcall(
        vim.lsp.util._get_line_byte_from_position,
        buf,
        hint.position,
        client.offset_encoding
      )
      if hint.position.line == row and (ok and byte or hint.position.character) == col then
        local name = vim.trim(label):gsub(":$", ""):gsub("=$", ""):gsub("^%$", ""):gsub("^%.%.%.", "")
        if name:match("^[%a_][%w_]*$") then
          return name
        end
      end
    end
  end
end

return M
