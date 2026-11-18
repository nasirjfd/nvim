-- Symbol pickers that start with the selected text (if any) as the query.
local M = {}

local function selection()
  local mode = vim.fn.mode()
  if not mode:match("^[vV\22]") then
    return nil
  end
  local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  local text = vim.trim(table.concat(lines, " "))
  return text ~= "" and text or nil
end

---@param workspace boolean all symbols of the project instead of the current file
function M.open(workspace)
  local text = selection()
  vim.cmd.stopinsert()
  local opts = text and (workspace and { search = text } or { pattern = text }) or nil
  if workspace then
    Snacks.picker.lsp_workspace_symbols(opts)
  elseif pcall(vim.treesitter.get_parser, 0) then
    -- Instant and independent of the language server (which may still be starting or indexing)
    Snacks.picker.treesitter(opts)
  else
    Snacks.picker.lsp_symbols(opts)
  end
end

return M
