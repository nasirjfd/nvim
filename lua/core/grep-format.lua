local M = {}

-- Keep the basename fixed. Only the directory gets a flexible/truncated field;
-- truncating the combined path first can eat the start of a long filename.
function M.format(item, picker)
  if not item.file then
    return Snacks.picker.format.file(item, picker)
  end
  local file = vim.tbl_extend("force", picker.opts.formatters.file, { filename_only = true })
  local formatters = vim.tbl_extend("force", picker.opts.formatters, { file = file })
  local opts = vim.tbl_extend("force", picker.opts, { formatters = formatters })
  local proxy = setmetatable({ opts = opts }, { __index = picker })
  local ret = Snacks.picker.format.file(item, proxy)
  local dir = vim.fs.dirname(Snacks.picker.util.path(item) or item.file)
  if not dir or dir == "." or dir == vim.fs.normalize(picker:cwd()) then
    return ret
  end
  for index, chunk in ipairs(ret) do
    if chunk.field == "file" then
      table.insert(ret, index + 1, {
        "",
        resolve = function(width)
          if width <= 1 then
            return {}
          end
          local shortened = Snacks.picker.util.truncpath(dir, width - 1, {
            cwd = picker:cwd(),
            kind = "left",
          })
          return { { " " .. shortened, "SnacksPickerDir", field = "file" } }
        end,
      })
      break
    end
  end
  return ret
end

return M
