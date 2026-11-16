-- Start workspace LSP clients declared by a trusted project-local .nvim.lua.
--
-- Example:
--   vim.g.project_lsp_filetypes = { "php", "typescript" }
--
-- Server selection comes exclusively from each enabled native LSP config's
-- `filetypes` field. This keeps project configs independent of server names.
local M = {}

local function normalize(path)
  return path and vim.fs.normalize(path) or nil
end

local function has_client(name, root)
  for _, client in ipairs(vim.lsp.get_clients({ name = name })) do
    local client_root = client.root_dir or client.config.root_dir
    if normalize(client_root) == root then
      return true
    end
  end
  return false
end

local function start_for_filetype(filetype, root)
  for _, config in ipairs(vim.lsp.get_configs()) do
    if vim.lsp.is_enabled(config.name) and vim.tbl_contains(config.filetypes or {}, filetype) then
      if not has_client(config.name, root) then
        local client_config = vim.tbl_extend("force", {}, config, {
          root_dir = root,
          workspace_folders = {
            {
              uri = vim.uri_from_fname(root),
              name = vim.fs.basename(root),
            },
          },
        })
        vim.lsp.start(client_config, { attach = false })
      end
    end
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("ProjectLspBootstrap", { clear = true }),
    once = true,
    callback = function()
      local filetypes = vim.g.project_lsp_filetypes
      if type(filetypes) ~= "table" then
        return
      end

      local root = normalize(vim.fn.getcwd())
      if not root or root == "" then
        return
      end

      vim.schedule(function()
        for _, filetype in ipairs(filetypes) do
          if type(filetype) == "string" and filetype ~= "" then
            start_for_filetype(filetype, root)
          end
        end
      end)
    end,
  })
end

return M
