-- The requests of an .http file, from its lines (pure: no buffers, no files).
--
-- A request starts at a `###` line (or at the top of the file) and lasts until the next `###`. Its
-- name is, like in Kulala: `# @name x` first, else the text after `###`, else "METHOD url". The request
-- line is the first line that is not a comment and starts with an HTTP method.
local M = {}

local METHODS = {
  GET = true, POST = true, PUT = true, PATCH = true, DELETE = true, HEAD = true, OPTIONS = true,
  TRACE = true, CONNECT = true, GRAPHQL = true, GRPC = true, WEBSOCKET = true,
}
M.METHODS = METHODS

---@class http.Request
---@field name string
---@field method string
---@field url string
---@field line integer  the request line (METHOD url), 1-based
---@field start_line integer  first line of the block (the `###` line, or 1)
---@field end_line integer

---@param lines string[]
---@return http.Request[]
function M.parse(lines)
  local requests = {}
  local start, title = 1, ""

  local function finish(last)
    local name, method, url, request_line
    for lnum = start, last do
      local line = lines[lnum]
      if lnum > start or not line:find("^###") then
        local tag = line:match("^%s*[#/]+%s*@name%s+(%S+)")
        if tag and not name then
          name = tag
        end
        if not request_line and not line:find("^%s*[#/]") then
          local m, u = line:match("^%s*(%u+)%s+(%S+)")
          if m and METHODS[m] then
            method, url, request_line = m, u, lnum
          end
        end
      end
    end
    if request_line then
      if not name and title ~= "" then
        name = title
      end
      requests[#requests + 1] = {
        name = name or (method .. " " .. url),
        method = method,
        url = url,
        line = request_line,
        start_line = start,
        end_line = last,
      }
    end
  end

  for lnum, line in ipairs(lines) do
    if line:find("^###") and lnum > 1 then
      finish(lnum - 1)
      start, title = lnum, vim.trim(line:gsub("^#+", ""))
    elseif line:find("^###") then
      title = vim.trim(line:gsub("^#+", ""))
    end
  end
  finish(#lines)
  return requests
end

return M
