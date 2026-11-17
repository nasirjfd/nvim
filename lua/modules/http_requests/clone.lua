-- Copy a complete request into the current HTTP buffer without executing it or changing its source.
local M = {}
local api = vim.api
local parse = require("modules.http_requests.parse")

function M.items(root, paths)
  local items = {}
  for _, rel in ipairs(paths) do
    local path = vim.fs.joinpath(root, rel)
    local buf = vim.fn.bufnr(path)
    local lines
    if buf ~= -1 and api.nvim_buf_is_loaded(buf) then
      lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    else
      local ok, content = pcall(vim.fn.readfile, path)
      lines = ok and content or {}
    end
    for _, request in ipairs(parse.parse(lines)) do
      items[#items + 1] = {
        text = request.name .. " · " .. request.method .. " · " .. rel,
        name = request.name,
        file = path,
        pos = { request.line, 0 },
        lines = vim.list_slice(lines, request.start_line, request.end_line),
      }
    end
  end
  return items
end

function M.insert(buf, row, lines)
  if not api.nvim_buf_is_valid(buf) or not vim.bo[buf].modifiable or vim.bo[buf].readonly then
    return false
  end
  local block = vim.deepcopy(lines)
  while #block > 0 and block[#block]:match("^%s*$") do
    table.remove(block)
  end
  if not (block[1] or ""):match("^###") then
    table.insert(block, 1, "###")
  end
  row = math.min(row, api.nvim_buf_line_count(buf))
  local first = row
  if row > 0 and api.nvim_buf_get_lines(buf, row - 1, row, false)[1] ~= "" then
    table.insert(block, 1, "")
    first = first + 1
  end
  block[#block + 1] = ""
  api.nvim_buf_set_lines(buf, row, row, false, block)
  return first + 1
end

function M.open()
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local row, tick = api.nvim_win_get_cursor(win)[1] - 1, api.nvim_buf_get_changedtick(buf)
  local root = vim.fn.getcwd()
  local files = require("core.http-files")
  files.scan(root, function()
    if
      not api.nvim_win_is_valid(win)
      or not api.nvim_buf_is_valid(buf)
      or api.nvim_get_current_win() ~= win
      or api.nvim_win_get_buf(win) ~= buf
    then
      return
    end
    local paths = vim.deepcopy(files.cached(root) or {})
    local current = api.nvim_buf_get_name(buf)
    local rel = vim.fs.relpath(root, current)
    if rel and not vim.tbl_contains(paths, rel) then
      paths[#paths + 1] = rel
    end
    local items = M.items(root, paths)
    if #items == 0 then
      vim.notify("No HTTP requests found in this project", vim.log.levels.INFO)
      return
    end
    Snacks.picker.pick({
      title = "Clone HTTP request here",
      items = items,
      format = "text",
      layout = { preset = "vertical" },
      preview = function(ctx)
        ctx.preview:set_lines(ctx.item.lines)
        ctx.preview:highlight({ ft = "http" })
      end,
      confirm = function(picker, item)
        picker:close()
        if not item or not api.nvim_buf_is_valid(buf) then
          return
        end
        if api.nvim_buf_get_changedtick(buf) ~= tick then
          vim.notify("HTTP buffer changed: open the clone picker again", vim.log.levels.WARN)
          return
        end
        local line = M.insert(buf, row, item.lines)
        if line and api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
          api.nvim_set_current_win(win)
          api.nvim_win_set_cursor(win, { line, 0 })
        end
      end,
    })
  end)
end

return M
