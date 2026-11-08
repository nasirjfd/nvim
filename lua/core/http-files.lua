-- <leader>hh: pick an .http file of the project, like cmd+e: the file opened last is at the top
-- (only when it was opened counts, not how often), then the rest by name.
--
-- Every .http file under the working directory is listed, hidden ones too, except what git ignores.
-- The list is cached per directory (in memory and on disk), so the picker opens with it at once; fd
-- runs in the background on each open and the list is updated in place if a file was added,
-- moved or removed. When each .http file was last opened is kept on disk too.
local M = {}

local api = vim.api
local uv = vim.uv
local state_file = vim.fn.stdpath("state") .. "/http-files.json"

local state -- { lists = { [cwd] = { "rel/path.http", ... } }, opened = { [abs path] = epoch seconds } }

local function load()
  if state then
    return state
  end
  state = { lists = {}, opened = {} }
  local fd = io.open(state_file, "r")
  if fd then
    local ok, data = pcall(vim.json.decode, fd:read("*a"))
    fd:close()
    if ok and type(data) == "table" then
      state.lists = type(data.lists) == "table" and data.lists or {}
      state.opened = type(data.opened) == "table" and data.opened or {}
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

-- One spelling per file for `opened` (the same folder can be reached as ~/Can/… and ~/can/… on
-- macOS, whose disk ignores case)
local function key(path)
  return (uv.fs_realpath(path) or vim.fs.normalize(path)):lower()
end

-- Rows for the picker: last opened first, then the others by name.
local function items(dir)
  local s = load()
  local list = s.lists[dir] or {}
  local rows = {}
  for _, rel in ipairs(list) do
    local abs = dir .. "/" .. rel
    rows[#rows + 1] = { file = abs, text = rel, opened = s.opened[key(abs)] or 0 }
  end
  table.sort(rows, function(a, b)
    if a.opened ~= b.opened then
      return a.opened > b.opened
    end
    return a.text < b.text
  end)
  return rows
end

-- List the .http files of `dir` again with fd; done(changed) on the main loop.
local function scan(dir, done)
  vim.system(
    { "fd", "--type", "f", "--extension", "http", "--hidden", "--exclude", ".git", "--color", "never", "." },
    { cwd = dir, text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        return done(false)
      end
      local list = {}
      for line in result.stdout:gmatch("[^\n]+") do
        list[#list + 1] = (line:gsub("^%./", ""))
      end
      table.sort(list)
      local s = load()
      local changed = not vim.deep_equal(s.lists[dir], list)
      if changed then
        s.lists[dir] = list
        save()
      end
      done(changed)
    end)
  )
end

function M.pick()
  if vim.fn.executable("fd") == 0 then
    vim.notify("fd is not installed (brew install fd)", vim.log.levels.WARN)
    return
  end
  local dir = cwd()
  local function open()
    return Snacks.picker.pick({
      source = "http_files",
      title = "HTTP Files",
      finder = function()
        return items(dir)
      end,
      format = "file",
      preview = "file",
      show_empty = true,
      -- keep this order (last opened first) until something is typed
      matcher = { sort_empty = false, frecency = false },
      sort = { fields = { "score:desc", "idx" } },
    })
  end
  if not load().lists[dir] then
    -- Nothing cached for this folder yet: list it first (fd takes a few tens of ms)
    scan(dir, open)
    return
  end
  local picker = open()
  -- Bring the cache up to date; the open picker follows when a file was added, moved or removed
  scan(dir, function(changed)
    if changed and picker and not picker.closed then
      picker:find()
    end
  end)
end

local group = api.nvim_create_augroup("HttpFiles", { clear = true })
api.nvim_create_autocmd("BufEnter", {
  group = group,
  pattern = "*.http",
  callback = function(args)
    local file = api.nvim_buf_get_name(args.buf)
    if file ~= "" then
      local sec, usec = uv.gettimeofday()
      load().opened[key(file)] = sec + usec / 1e6
      save()
    end
  end,
})
-- A new .http file shows up in the cached list right away
api.nvim_create_autocmd("BufWritePost", {
  group = group,
  pattern = "*.http",
  callback = function(args)
    local dir, file = cwd(), vim.fs.normalize(api.nvim_buf_get_name(args.buf))
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

vim.keymap.set("n", "<leader>hh", M.pick, { desc = "HTTP files (last opened first)" })

return M
