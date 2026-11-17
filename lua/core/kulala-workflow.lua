-- Persist only environment names (never variables/secrets), and hide responses on editor-file exits.
local M = {}
local api = vim.api
local restoring = false
local active_root
local state_file = vim.fn.stdpath("state") .. "/kulala-environments.json"

local function http(buf)
  return vim.bo[buf].buftype == ""
    and (vim.bo[buf].filetype == "http" or vim.bo[buf].filetype == "rest")
end

local function root(buf)
  local file = api.nvim_buf_get_name(buf)
  local dir = file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
  local env = vim.fs.find({ "http-client.env.json", "http-client.private.env.json" }, {
    path = dir,
    upward = true,
  })[1]
  return vim.fs.normalize(env and vim.fs.dirname(env) or vim.fn.getcwd())
end

local function load()
  local ok, lines = pcall(vim.fn.readfile, state_file)
  if ok then
    local decoded, data = pcall(vim.json.decode, table.concat(lines, "\n"))
    if decoded and type(data) == "table" then
      return data
    end
  end
  return {}
end

function M.remember_env()
  local env = vim.g.kulala_selected_env
  if restoring or not active_root or type(env) ~= "string" or env == "" then
    return
  end
  local data = load()
  data[active_root] = env
  vim.fn.mkdir(vim.fn.fnamemodify(state_file, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(data) }, state_file)
end

function M.restore(buf)
  if not http(buf) then
    return
  end
  local selected_root = root(buf)
  if selected_root == active_root then
    return
  end
  M.remember_env()
  active_root = selected_root
  restoring = true
  local env = load()[active_root]
  vim.g.kulala_selected_env = type(env) == "string" and env or nil
  restoring = false
end

function M.setup()
  local group = api.nvim_create_augroup("KulalaWorkflow", { clear = true })
  -- Kulala's picker assigns the global directly, bypassing set_selected_env(). Observe that actual
  -- assignment so selections survive both a normal exit and a later crash.
  if not vim.g.kulala_env_watcher_installed then
    vim.cmd(
      [[call dictwatcheradd(g:, 'kulala_selected_env', {d,k,c -> luaeval("require('core.kulala-workflow').remember_env()")})]]
    )
    vim.g.kulala_env_watcher_installed = true
  end
  api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
    group = group,
    callback = function(args)
      M.restore(args.buf)
    end,
  })
  api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.remember_env })
  api.nvim_create_autocmd({ "BufEnter", "TabEnter" }, {
    group = group,
    callback = function()
      local buf = api.nvim_get_current_buf()
      local name = api.nvim_buf_get_name(buf)
      if vim.bo[buf].buftype ~= "" or http(buf) or name:match("^kulala://") then
        return
      end
      vim.schedule(function()
        if api.nvim_get_current_buf() == buf then
          require("core.kulala-ui").hide_response()
        end
      end)
    end,
  })
  M.restore(api.nvim_get_current_buf())
end

return M
