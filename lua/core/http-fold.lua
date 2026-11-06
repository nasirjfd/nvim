-- Folding of .http files by request: every `###` line starts a fold that lasts until the next one,
-- shown as one line: the request's name, then its method and URL. `zM` collapses all requests (to see
-- the names), `zo`/`za` open one, `zR` opens all.
local M = {}

local METHODS = "^%s*(%u+)%s+(%S+)"

function M.expr(lnum)
  local line = vim.fn.getline(lnum)
  if line:find("^###") then
    return ">1"
  end
  return "="
end

function M.text()
  local first, last = vim.v.foldstart, vim.v.foldend
  local title = vim.trim((vim.fn.getline(first):gsub("^#+", "")))
  local method, url
  for lnum = first + 1, last do
    local line = vim.fn.getline(lnum)
    local name = line:match("^%s*[#/]+%s*@name%s+(%S+)")
    if name and title == "" then
      title = name
    end
    local m, u = line:match(METHODS)
    if m and not line:find("^%s*[#/]") and (m == "GET" or m == "POST" or m == "PUT" or m == "PATCH" or m == "DELETE" or m == "HEAD" or m == "OPTIONS" or m == "GRAPHQL" or m == "GRPC" or m == "WEBSOCKET") then
      method, url = m, u
      break
    end
  end
  local chunks = { { "▸ " .. (title ~= "" and title or "(unnamed)"), "Title" } }
  if method then
    chunks[#chunks + 1] = { "  " .. method, "Keyword" }
    chunks[#chunks + 1] = { " " .. url, "Comment" }
  end
  chunks[#chunks + 1] = { ("  (%d lines)"):format(last - first + 1), "NonText" }
  return chunks
end

return M
