local M = {}

-- jq preserves JSON numbers/escapes without round-tripping through Lua values.
function M.json(lines)
  local text = table.concat(lines, "\n")
  if not text:match("^%s*[%[{]") or vim.fn.executable("jq") == 0 then
    return nil
  end
  local result = vim.system({ "jq", "--indent", "2", "." }, { stdin = text, text = true }):wait()
  if result.code == 0 then
    return vim.split(vim.trim(result.stdout), "\n", { plain = true })
  end
end

function M.format()
  local range
  local mode = vim.api.nvim_get_mode().mode
  if mode == "v" or mode == "V" or mode == "\22" then
    local first, last = vim.fn.line("v"), vim.fn.line(".")
    if first > last then
      first, last = last, first
    end
    range = { start = { first, 0 }, ["end"] = { last, #vim.fn.getline(last) } }
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  end
  if vim.bo.filetype == "http" or vim.bo.filetype == "rest" then
    local first, last = range and range.start[1] - 1 or 0, range and range["end"][1] or -1
    local lines = vim.api.nvim_buf_get_lines(0, first, last, false)
    local formatted = M.json(lines)
    if formatted then
      vim.api.nvim_buf_set_lines(0, first, last, false, formatted)
    else
      vim.notify("Select a complete JSON body to format", vim.log.levels.INFO)
    end
    return
  end
  -- Pint and other whole-file tools still process the entire buffer for a selection.
  -- Prefer an already-running range formatter; apply its edits before the shortcut returns.
  require("conform").format({
    async = false,
    timeout_ms = 1000,
    range = range,
    lsp_format = range and "prefer" or "fallback",
  }, function(err)
    if err then
      vim.notify(err, vim.log.levels.WARN, { title = "Format" })
    end
  end)
end

return M
