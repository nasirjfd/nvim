-- HTTP previews may be loaded before FileType's tree-sitter hook, or while a parser is being installed.
-- Check the actual highlighter, not just whether Kulala/the parser module has loaded.
local M = {}
local pending = {}
local api = vim.api

local function is_http(buf)
  if not api.nvim_buf_is_valid(buf) or not api.nvim_buf_is_loaded(buf) then
    return false
  end
  local name = api.nvim_buf_get_name(buf)
  return vim.bo[buf].filetype == "http" or vim.bo[buf].filetype == "rest"
    or name:match("%.http$") ~= nil or name:match("%.rest$") ~= nil
end

local function start(buf)
  if not is_http(buf) then
    return false
  end
  -- A buffer loaded by a sidebar preview may have missed filetype detection entirely.
  if vim.bo[buf].filetype == "" then
    api.nvim_buf_call(buf, function()
      vim.bo[buf].filetype = "http"
    end)
  end
  if vim.treesitter.highlighter.active[buf] then
    return true
  end
  -- Kulala's grammar is named kulala_http, not http. Resolve the registered filetype mapping.
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype) or "kulala_http"
  local ok = pcall(vim.treesitter.start, buf, lang)
  return ok and vim.treesitter.highlighter.active[buf] ~= nil
end

function M.ensure(buf)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  if not is_http(buf) or start(buf) or pending[buf] then
    return
  end
  -- Leave syntax highlighting enabled while tree-sitter is unavailable. Retry without blocking input;
  -- later BufWinEnter/BufEnter events can retry again if installation takes longer than this window.
  vim.bo[buf].syntax = "http"
  pending[buf] = true
  local attempts = 0
  local function retry()
    attempts = attempts + 1
    if not is_http(buf) or start(buf) or attempts >= 40 then
      pending[buf] = nil
      return
    end
    vim.defer_fn(retry, 100)
  end
  vim.defer_fn(retry, 50)
end

function M.setup()
  api.nvim_create_autocmd({ "FileType", "BufEnter", "BufWinEnter", "CursorHold" }, {
    group = api.nvim_create_augroup("HttpHighlightRecovery", { clear = true }),
    callback = function(args)
      M.ensure(args.buf)
    end,
  })
end

return M
