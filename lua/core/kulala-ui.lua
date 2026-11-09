-- Hiding Kulala's response window safely.
--
-- Kulala hides it by deleting its buffer, which closes the window as a side effect. After an LSP
-- hover (gh) Neovim watches every closing window and reads that window's variables; a window closed
-- through a buffer delete is already gone by then, and Neovim raises "Invalid window id". Closing
-- the window first, while it is still valid, and deleting the buffer after avoids that.
local M = {}

function M.hide_response()
  local ok, ui = pcall(require, "kulala.ui")
  if not ok then
    return false
  end
  local buf = ui.get_kulala_buffer()
  if not buf then
    return false
  end
  local shown = false
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    shown = true
    if #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win)) > 1 then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  pcall(ui.close_kulala_buffer)
  return shown
end

-- HTML responses filtered by a CSS selector, written by hand at one of three levels; the most
-- specific one wins:
--   1. request:  a `# @css <selector>` line in the request, like Kulala's `# @jq`
--   2. file:     a `@css = <selector>` variable in the file (at the top: every request of the file)
--   3. global:   a "css" entry in http-client.env.json, under "$shared" (every request) or an env
-- Only HTML responses are filtered (htmlq). The response then starts with a comment naming the
-- selector and where it came from, followed by the matches. A selector ending in ::text shows the
-- values the matches hold, one per match and coloured like JSON: JSON (also inside a string) is
-- formatted, a string is shown in "", a number, true, false or null without quotes. Without ::text
-- the matching HTML elements are shown. `none` turns it off (`# @css none`).

local function is_html(response)
  local headers = type(response.headers) == "string" and response.headers or ""
  if headers:lower():find("content%-type:%s*[^\n]*html") then
    return true
  end
  local body = response.body
  return type(body) == "string" and body:match("^%s*<") ~= nil and not body:match("^%s*<%?xml")
end

-- The selector for a request and where it came from, or nil.
local function selector_for(request)
  for _, meta in ipairs(request.metadata or {}) do
    if meta.name == "css" and meta.value and vim.trim(meta.value) ~= "" then
      return vim.trim(meta.value), "request"
    end
  end
  local file = (request.variables or {}).css or ((request.shared or {}).variables or {}).css
  if file and vim.trim(tostring(file)) ~= "" then
    return vim.trim(tostring(file)), "file"
  end
  local global = (request.environment or {}).css
  if global and vim.trim(tostring(global)) ~= "" then
    return vim.trim(tostring(global)), "global"
  end
end

-- A matched text as a JSON-like value: JSON objects and arrays formatted (jq), a symfony dump of a
-- string ("text") or any other text as a quoted string, numbers and true/false/null as they are.
-- A multi-line text that is none of those (a dumped PHP array) is kept as it is.
local function json_string(text)
  return '"' .. text:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\t", "\\t") .. '"'
end

-- A dumped PHP array ("array:2 [ \"id\" => 1 ... ]", as Symfony's dump() prints it) as JSON text,
-- keys in their order: a list when the keys are 0, 1, 2…, an object otherwise. nil when the dump
-- holds anything else (objects, multi-line strings), which is then shown as dumped.
local function dump_to_json(text)
  local lines = vim.split(text, "\n", { plain = true })
  local pos = 1
  local scalar
  local function parse_value(v, depth)
    v = vim.trim(v)
    if v == "[]" then
      return "[]"
    end
    if v:match("^array:%d+ %[$") then
      local entries, list = {}, true
      while true do
        pos = pos + 1
        local line = lines[pos]
        if not line then
          return nil
        end
        line = vim.trim(line)
        if line == "]" then
          break
        end
        local key, rest = line:match("^(.-) => (.*)$")
        if not key then
          return nil
        end
        local value = parse_value(rest, depth + 1)
        if not value then
          return nil
        end
        local k = key:match('^"(.*)"$')
        if k or tonumber(key) ~= #entries then
          list = false
        end
        entries[#entries + 1] = { k or key, value }
      end
      if #entries == 0 then
        return "[]"
      end
      local pad, inner = string.rep("  ", depth), string.rep("  ", depth + 1)
      local out = {}
      for _, e in ipairs(entries) do
        out[#out + 1] = inner .. (list and "" or (scalar(e[1]) .. ": ")) .. e[2]
      end
      return (list and "[" or "{") .. "\n" .. table.concat(out, ",\n") .. "\n" .. pad .. (list and "]" or "}")
    end
    local str = v:match('^"(.*)"$')
    if str then
      return scalar(str)
    end
    if tonumber(v) or v == "true" or v == "false" or v == "null" then
      return v
    end
    return nil
  end
  scalar = function(str)
    return '"' .. str:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
  end
  local result = parse_value(lines[1], 0)
  if result and pos == #lines then
    return result
  end
end

local function as_value(text)
  -- In a web page Symfony starts each dump with "^", a link to the file and line of the dump() call
  text = vim.trim(text):gsub("^%^%s+", "")
  local quoted = text:match('^"(.*)"$')
  local inner = quoted or text
  if inner:match("^%s*[%[{]") then
    local result = vim.system({ "jq", "." }, { stdin = inner, text = true }):wait()
    if result.code == 0 and vim.trim(result.stdout) ~= "" then
      return vim.trim(result.stdout)
    end
  end
  if quoted then
    return json_string(quoted)
  end
  if tonumber(text) or text == "true" or text == "false" or text == "null" then
    return text
  end
  if text:find("\n") then
    return dump_to_json(text) or text
  end
  return json_string(text)
end

local function apply_css(request, response)
  local selector, level = selector_for(request)
  if not selector or selector == "none" or not is_html(response) then
    return
  end
  if vim.fn.executable("htmlq") == 0 then
    vim.notify("htmlq is not installed (brew install htmlq): the @css filter is skipped", vim.log.levels.WARN)
    return
  end
  local css, text_only = selector:gsub("%s*::text$", "")
  local cmd = text_only > 0 and { "htmlq", "--text", css } or { "htmlq", css }
  local result = vim.system(cmd, { stdin = response.body, text = true }):wait()
  local header = ("<!-- css (%s): %s -->"):format(level, selector)
  if result.code == 0 and text_only > 0 then
    -- each match's text ends with a line break and htmlq adds one, so matches are apart by a blank line
    local values = {}
    for chunk in (result.stdout .. "\n\n"):gmatch("(.-)\n%s*\n") do
      if vim.trim(chunk) ~= "" then
        values[#values + 1] = as_value(chunk)
      end
    end
    response.body = ("// css (%s): %s\n\n"):format(level, selector) .. (#values > 0 and table.concat(values, "\n") or "// nothing matches")
    -- shown with JSON colours, as written here (no formatter: see contenttypes in plugins/kulala.lua)
    response.headers = response.headers:gsub("([Cc]ontent%-[Tt]ype:%s*)[^\r\n]*", "%1kulala/values", 1)
    return
  end
  if result.code ~= 0 then
    response.body = header .. "\n<!-- htmlq: " .. vim.trim(result.stderr or "invalid selector") .. " -->\n" .. response.body
    return
  end
  local matches = vim.tbl_filter(function(line)
    return vim.trim(line) ~= ""
  end, vim.split(result.stdout, "\n", { plain = true }))
  if #matches == 0 then
    matches = { "<!-- nothing matches -->" }
  end
  response.body = header .. "\n\n" .. table.concat(matches, "\n")
end

-- Run the filter where Kulala post-processes every response (its post-request scripts step).
function M.setup_css()
  local scripts = require("kulala.parser.scripts")
  if scripts._css_wrapped then
    return
  end
  scripts._css_wrapped = true
  local run = scripts.run
  scripts.run = function(kind, request, response, ...)
    if kind == "post_request" and response then
      local ok, err = pcall(apply_css, request, response)
      if not ok then
        vim.notify("css filter: " .. tostring(err), vim.log.levels.WARN)
      end
    end
    return run(kind, request, response, ...)
  end
end

return M
