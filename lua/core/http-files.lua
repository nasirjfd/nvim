-- The .http / .rest files of the project (for the HTTP Requests pane, lua/modules/http_requests).
--
-- Every file under the working directory is listed, hidden ones too, except what git ignores. The list is
-- cached per directory (in memory and on disk), so the pane opens with it at once; fd runs in the
-- background on each open and the pane is told if a file was added, moved or removed.
local M = {}

local api = vim.api
local uv = vim.uv
local state_file = vim.fn.stdpath("state") .. "/http-files.json"

local state -- {
--   lists = { [cwd] = { "rel/path.http", ... } },
--   envs = { [cwd] = { "http-client.env.json", ... } },
-- }

local function load()
  if state then
    return state
  end
  state = { lists = {}, envs = {} }
  local fd = io.open(state_file, "r")
  if fd then
    local ok, data = pcall(vim.json.decode, fd:read("*a"))
    fd:close()
    if ok and type(data) == "table" then
      state.lists = type(data.lists) == "table" and data.lists or {}
      state.envs = type(data.envs) == "table" and data.envs or {}
    end
  end
  return state
end

local save_pending = false
local function save()
  if save_pending then
    return
  end
  save_pending = true
  vim.defer_fn(function()
    save_pending = false
    vim.fn.mkdir(vim.fn.fnamemodify(state_file, ":h"), "p")
    local fd = io.open(state_file, "w")
    if fd then
      fd:write(vim.json.encode(state))
      fd:close()
    end
  end, 200)
end

local function cwd()
  return uv.cwd() or vim.fn.getcwd()
end

-- List the .http files of `dir` again with fd; done(changed) on the main loop.
local function scan(dir, done)
  vim.system(
    {
      "fd", "--type", "f", "--hidden", "--exclude", ".git", "--color", "never",
      "\\.http$|\\.rest$|^http-client(\\.private)?\\.env\\.json$", ".",
    },
    { cwd = dir, text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        return done(false)
      end
      local list, envs = {}, {}
      for line in result.stdout:gmatch("[^\n]+") do
        local rel = line:gsub("^%./", "")
        local is_env = vim.endswith(rel, "http-client.env.json")
          or vim.endswith(rel, "http-client.private.env.json")
        if is_env then
          envs[#envs + 1] = rel
        else
          list[#list + 1] = rel
        end
      end
      table.sort(list)
      table.sort(envs)
      local s = load()
      local changed = not vim.deep_equal(s.lists[dir], list)
        or not vim.deep_equal(s.envs[dir], envs)
      if changed then
        s.lists[dir] = list
        s.envs[dir] = envs
        save()
      end
      done(changed)
    end)
  )
end

--- The cached list of `dir` (relative paths), or nil when it was never listed.
function M.cached(dir)
  return load().lists[dir]
end

function M.cached_envs(dir)
  return load().envs[dir]
end

M.scan = scan

local group = api.nvim_create_augroup("HttpFiles", { clear = true })
-- A new .http file shows up in the cached list right away
api.nvim_create_autocmd("BufWritePost", {
  group = group,
  pattern = { "*.http", "*.rest", "http-client.env.json", "http-client.private.env.json" },
  callback = function(args)
    local dir, file = cwd(), vim.fs.normalize(api.nvim_buf_get_name(args.buf))
    local name = vim.fn.fnamemodify(file, ":t")
    local env = name == "http-client.env.json" or name == "http-client.private.env.json"
    if env then
      local list = load().envs[dir]
      if not list or file:sub(1, #dir + 1) ~= dir .. "/" then
        return
      end
      local rel = file:sub(#dir + 2)
      if not vim.tbl_contains(list, rel) then
        list[#list + 1] = rel
        table.sort(list)
        save()
      end
      return
    end
    local list = load().lists[dir]
    if not list or file:sub(1, #dir + 1) ~= dir .. "/" then
      return
    end
    local rel = file:sub(#dir + 2)
    if not vim.tbl_contains(list, rel) then
      list[#list + 1] = rel
      table.sort(list)
      save()
    end
  end,
})

return M
