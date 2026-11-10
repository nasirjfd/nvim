-- A curl command (from the clipboard) as the lines of an .http request.
--
-- The parsing is Kulala's own pure curl parser (the only place this module depends on Kulala's
-- internals; pinned at v5.3.4 in lua/plugins/kulala.lua). Nothing is inserted anywhere here.
local M = {}

M.INVALID = "The clipboard does not hold a valid curl command"

---@param text string?
---@return string[]? lines, string? err
function M.to_lines(text)
  text = vim.trim(text or "")
  if text == "" then
    return nil, M.INVALID
  end
  local ok, spec = pcall(function()
    return require("kulala.parser.curl").parse(text)
  end)
  if not ok or type(spec) ~= "table" or not spec.url or vim.trim(spec.url) == "" or not spec.method then
    return nil, M.INVALID
  end

  local lines = { ("### %s %s"):format(spec.method, spec.url) }
  lines[#lines + 1] = ("%s %s%s"):format(spec.method, spec.url, (spec.http_version and spec.http_version ~= "") and (" " .. spec.http_version) or "")
  local names = vim.tbl_keys(spec.headers or {})
  table.sort(names)
  for _, name in ipairs(names) do
    lines[#lines + 1] = ("%s: %s"):format(name, spec.headers[name])
  end
  if spec.cookie and spec.cookie ~= "" then
    lines[#lines + 1] = "Cookie: " .. spec.cookie
  end
  local body = spec.body
  if type(body) == "string" then
    body = { body }
  end
  if body and #body > 0 then
    lines[#lines + 1] = ""
    for _, line in ipairs(body) do
      lines[#lines + 1] = line
    end
  end
  return lines
end

return M
