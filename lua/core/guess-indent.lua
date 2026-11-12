-- ============================================================================
-- Indentation of the file as it is. When a file is opened, shiftwidth / tabstop / expandtab are taken
-- from its own text, so `o` / `O` (treesitter indent) and >> follow the file's formatting: 4 spaces,
-- 2 spaces or tabs, instead of the global shiftwidth of core/options.lua. A project's .editorconfig
-- wins (Neovim applies it itself and sets vim.b.editorconfig). Pure detection is `M.detect(lines)`.
-- ============================================================================
local M = {}

local SAMPLE = 1000 -- lines looked at
local WIDTHS = { [2] = true, [3] = true, [4] = true, [8] = true }

--- What the text uses: { expandtab = bool, width = n } or nil when it cannot tell (no indented lines).
function M.detect(lines)
  local tabs, spaces = 0, 0
  local deltas = {}
  local previous = 0
  local in_comment = false
  for i = 1, math.min(#lines, SAMPLE) do
    local line = lines[i]
    if line:match("%S") then
      -- the lines of a /* ... */ block start with " *": their one space is not indentation
      local starts_comment = line:match("^%s*/%*") ~= nil
      local continues = in_comment or line:match("^%s*%*") ~= nil
      if starts_comment and not line:find("%*/") then
        in_comment = true
      end
      if in_comment and line:find("%*/") then
        in_comment = false
      end
      if not continues and not starts_comment then
        local lead = line:match("^(%s*)")
        if lead:sub(1, 1) == "\t" then
          tabs = tabs + 1
          previous = 0
        elseif #lead > 0 then
          spaces = spaces + 1
          local width = #lead
          local delta = width - previous
          if delta > 0 and WIDTHS[delta] then
            deltas[delta] = (deltas[delta] or 0) + 1
          end
          previous = width
        else
          previous = 0
        end
      end
    end
  end
  if tabs == 0 and spaces == 0 then
    return nil
  end
  if tabs > spaces then
    return { expandtab = false }
  end
  local best, count = nil, 0
  for width, n in pairs(deltas) do
    if n > count or (n == count and best and width < best) then
      best, count = width, n
    end
  end
  if not best then
    return nil
  end
  return { expandtab = true, width = best }
end

--- Apply what the text of `buf` uses to its options.
function M.apply(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return
  end
  local editorconfig = vim.b[buf].editorconfig
  if type(editorconfig) == "table" and (editorconfig.indent_style or editorconfig.indent_size) then
    return
  end
  local found = M.detect(vim.api.nvim_buf_get_lines(buf, 0, SAMPLE, false))
  if not found then
    return
  end
  vim.bo[buf].expandtab = found.expandtab
  if found.width then
    vim.bo[buf].shiftwidth = found.width
    vim.bo[buf].softtabstop = found.width
  else
    vim.bo[buf].shiftwidth = 0 -- tabs: one level is one tab stop
    vim.bo[buf].softtabstop = 0
  end
end

function M.setup()
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = vim.api.nvim_create_augroup("GuessIndent", { clear = true }),
    callback = function(args)
      -- after the filetype plugins (they may set shiftwidth too), when the file is in the buffer
      vim.schedule(function()
        M.apply(args.buf)
      end)
    end,
  })
end

return M
