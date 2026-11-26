-- Swap syntax siblings, not lines: a function moves from its signature, a statement from its body.
local M = {}
local api = vim.api
local containers = {
  program = true,
  source_file = true,
  translation_unit = true,
  module = true,
  chunk = true,
  block = true,
  compound_statement = true,
  statement_block = true,
  statement_list = true,
  statements = true,
  declaration_list = true,
  class_body = true,
  interface_body = true,
}
local headers = { php_tag = true, package_clause = true, shebang = true, hash_bang_line = true }

local function comment(node)
  return node:type():find("comment", 1, true) ~= nil
end

local function attached(node)
  return comment(node) or node:type() == "attribute_item" or node:type() == "decorator"
end

local function bounds(node)
  local first, col, last, end_col = node:range()
  local start = node
  local previous = node:prev_named_sibling()
  while previous and attached(previous) do
    local row, _, finish, finish_col = previous:range()
    local finish_line = finish_col == 0 and finish - 1 or finish
    if finish_line < first - 1 then
      break
    end
    first, start = row, previous
    previous = previous:prev_named_sibling()
  end
  return {
    node = node,
    first = first,
    last = end_col == 0 and last or last + 1,
    start = start,
    col = col,
    end_col = end_col,
    end_row = last,
  }
end

local function full_lines(unit)
  local start_row, start_col = unit.start:range()
  local prefix = api.nvim_buf_get_lines(0, start_row, start_row + 1, false)[1]:sub(1, start_col)
  local suffix = unit.end_col == 0 and ""
    or api.nvim_buf_get_lines(0, unit.end_row, unit.end_row + 1, false)[1]:sub(unit.end_col + 1)
  return prefix:match("^%s*$")
    and (
      suffix:match("^%s*;?%s*$")
      or suffix:match("^%s*//")
      or suffix:match("^%s*%-%-")
      or suffix:match("^%s*#")
    )
end

local function once(direction, join)
  local cursor = api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local line = api.nvim_get_current_line()
  if line:match("^%s*$") then
    return false
  end
  local ok, parser = pcall(vim.treesitter.get_parser, 0)
  if not ok or not parser then
    return false
  end
  parser:parse()
  -- A nonempty range avoids ambiguous zero-width boundaries at a declaration's first byte.
  -- Leading indentation belongs to the statement on that line, not its surrounding class.
  local col = math.max(cursor[2], #(line:match("^%s*")))
  local node = parser:named_node_for_range({ row, col, row, col + 1 })
  while node and node:parent() and not containers[node:parent():type()] do
    node = node:parent()
  end
  if not node or not node:parent() then
    return false
  end
  local units, index = {}, nil
  for child in node:parent():iter_children() do
    if child:named() and not attached(child) then
      local unit = bounds(child)
      units[#units + 1] = unit
      if row >= unit.first and row < unit.last then
        index = #units
      end
    end
  end
  local current = index and units[index]
  local other = index and units[index + direction]
  if not current or not other then
    return false
  end
  for _, unit in ipairs({ current, other }) do
    if headers[unit.node:type()] or unit.node:has_error() or not full_lines(unit) then
      return false
    end
  end
  local top, bottom = current, other
  if direction < 0 then
    top, bottom = other, current
  end
  if top.last > bottom.first then
    return false -- two statements on one line cannot be swapped as line blocks
  end
  local replacement = api.nvim_buf_get_lines(0, bottom.first, bottom.last, false)
  vim.list_extend(replacement, api.nvim_buf_get_lines(0, top.last, bottom.first, false))
  vim.list_extend(replacement, api.nvim_buf_get_lines(0, top.first, top.last, false))
  if join then
    vim.cmd.undojoin()
  end
  api.nvim_buf_set_lines(0, top.first, bottom.last, false, replacement)
  local destination = direction < 0 and top.first or bottom.last - (current.last - current.first)
  api.nvim_win_set_cursor(0, { destination + row - current.first + 1, cursor[2] })
  return true
end

function M.move(direction)
  if not vim.bo.modifiable or vim.bo.readonly or vim.bo.buftype ~= "" then
    return
  end
  for i = 1, vim.v.count1 do
    if not once(direction, i > 1) then
      break
    end
  end
end

return M
