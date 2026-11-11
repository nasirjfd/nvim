-- The message of a failed test, shown under the line that failed (not at the end of it): a neotest consumer.
--
-- neotest's own diagnostic consumer makes a vim.diagnostic entry, which tiny-inline-diagnostic draws to the right of
-- the line; this one puts virtual lines under it instead, plus an error sign. Both follow the file when it is
-- edited (extmarks) and are redrawn after every run and whenever a test file is shown.
local M = {}

local api = vim.api
local ns = api.nvim_create_namespace("phpunit_messages")
local MAX_LINES = 6
local MAX_WIDTH = 200

local function set_highlights()
  api.nvim_set_hl(0, "PhpTestMessage", { link = "DiagnosticError", default = true })
  api.nvim_set_hl(0, "PhpTestMessageDim", { link = "Comment", default = true })
end
set_highlights()
api.nvim_create_autocmd("ColorScheme", { callback = set_highlights })

--- The virtual lines for a failure message: "● first line", "└ second line", then the rest indented. The message of
--- PHPUnit is the test's name, the error, a blank line and the stack trace: only what comes before the blank line.
---@param message string
---@return { [1]: string, [2]: string }[][] lines
function M.format(message)
  local text = {}
  for line in (message or ""):gmatch("([^\n]*)\n?") do
    if line == "" and #text > 0 then
      break
    end
    if line ~= "" then
      text[#text + 1] = vim.trim(line)
    end
  end
  if #text == 0 then
    text[1] = "failed"
  end
  local lines = {}
  for i = 1, math.min(#text, MAX_LINES) do
    local body = text[i]
    if vim.fn.strchars(body) > MAX_WIDTH then
      body = vim.fn.strcharpart(body, 0, MAX_WIDTH - 1) .. "…"
    end
    local lead = i == 1 and "● " or (i == 2 and "└ " or "  ")
    lines[#lines + 1] = { { " " .. lead, "PhpTestMessage" }, { body, "PhpTestMessage" } }
  end
  return lines
end

--- Show `failures` ({ { line = 0-based row, message = string } }) in `buf`, replacing what was shown there.
function M.render(buf, failures)
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local count = api.nvim_buf_line_count(buf)
  local used = {}
  for _, failure in ipairs(failures) do
    local row = math.min(math.max(failure.line, 0), count - 1)
    if not used[row] then
      used[row] = true
      api.nvim_buf_set_extmark(buf, ns, row, 0, {
        virt_lines = M.format(failure.message),
        sign_text = "󰅚",
        sign_hl_group = "DiagnosticSignError",
        priority = 1100,
      })
    end
  end
end

--- Called by neotest (a consumer) with its client.
function M.attach(client)
  local nio = require("nio")

  local function draw(adapter_id, files)
    local results = client:get_results(adapter_id)
    for file in pairs(files) do
      local buf = nio.fn.bufnr(file)
      if buf ~= -1 and nio.api.nvim_buf_is_loaded(buf) then
        local failures = {}
        local tree = client:get_position(file, { adapter = adapter_id })
        if tree then
          for _, node in tree:iter_nodes() do
            local data = node:data()
            local result = data.type == "test" and results[data.id]
            if result and result.status == "failed" and result.errors then
              for _, err in ipairs(result.errors) do
                failures[#failures + 1] = { line = err.line, message = err.message or result.short }
              end
            end
          end
        end
        nio.scheduler()
        M.render(buf, failures)
      end
    end
  end

  client.listeners.results = function(adapter_id, results)
    local files = {}
    for id in pairs(results) do
      local node = client:get_position(id, { adapter = adapter_id })
      if node and node:data().type ~= "dir" then
        files[node:data().path] = true
      end
    end
    draw(adapter_id, files)
  end
  client.listeners.run = function(adapter_id, _, ids)
    local files = {}
    for _, id in ipairs(ids) do
      local node = client:get_position(id, { adapter = adapter_id })
      if node and node:data().type ~= "dir" then
        files[node:data().path] = true
      end
    end
    draw(adapter_id, files)
  end
  client.listeners.test_file_focused = function(adapter_id, file)
    draw(adapter_id, { [file] = true })
  end
end

M.namespace = ns

return M
