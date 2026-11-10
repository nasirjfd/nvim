-- Adding a request block to an .http file, through its buffer (so an open, unsaved file keeps its edits).
local M = {}

M.NEW_REQUEST = { "### New request", "GET https://" }

--- Append `block` (lines, the first one a `###` line) to the end of `path`, after a blank line.
--- The file is created when it does not exist. It is saved only when it was unmodified before.
---@param path string
---@param block string[]
---@return integer start_line, integer request_line  1-based lines of the block's `###` and of its request line
function M.append(path, block)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  local was_modified = vim.bo[buf].modified
  local count = vim.api.nvim_buf_line_count(buf)
  local last = vim.api.nvim_buf_get_lines(buf, count - 1, count, false)[1]
  local empty = count == 1 and last == ""
  local lines = {}
  if not empty and last ~= "" then
    lines[#lines + 1] = "" -- a blank line between the requests
  end
  local start_line = (empty and 0 or count) + #lines + 1
  vim.list_extend(lines, block)
  vim.api.nvim_buf_set_lines(buf, empty and 0 or count, empty and -1 or count, false, lines)
  if not was_modified then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent noautocmd write")
    end)
    -- noautocmd skipped BufWritePost: tell the pane
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf })
  end
  return start_line, start_line + 1
end

return M
