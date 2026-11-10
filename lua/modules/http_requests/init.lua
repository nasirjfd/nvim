-- The HTTP Requests pane (<leader>h): a sidebar like the Explorer that lists the requests of the
-- project's .http / .rest files, grouped by folder and file.
--
--   Enter / click   go to the request in its file           (folders and files fold / unfold)
--   Ctrl+Enter / r  run the request (and go to it)
--   a               add a request to the file under the cursor (a folder asks for a new file name)
--   P               add the curl command in the clipboard as a request (a message when it is not valid)
--   R               list again                    q / Esc  close
--
-- It is a Snacks picker source (sidebar layout) so the tree, the window and the mouse come for free; the
-- parsing (parse.lua), the curl conversion (curl.lua) and the file edits (edit.lua) know nothing of it.
local parse = require("modules.http_requests.parse")
local curl = require("modules.http_requests.curl")
local edit = require("modules.http_requests.edit")
local files = require("core.http-files")
local kit = require("modules.pane_kit")

local M = {}

local SOURCE = "http_requests"
local api = vim.api
local uv = vim.uv

local last_file -- the .http file last gone to from the pane
local collapsed = {} -- item key -> true while folded
local parsed = {} -- abs path -> { stamp, requests }

local function cwd()
  return uv.cwd() or vim.fn.getcwd()
end

-- ── highlights ──────────────────────────────────────────────────────────────────────────────────
local function set_highlights()
  local function hl(name, opts)
    opts.default = true
    api.nvim_set_hl(0, name, opts)
  end
  -- the method is only a coloured word (no badge): muted tones that do not shout next to the names
  for method, fg in pairs({
    GET = "#7fa585", POST = "#b59a72", PUT = "#7d9bbf", PATCH = "#9d8bb5", DELETE = "#b07a80",
    HEAD = "#8a949c", OPTIONS = "#8a949c",
  }) do
    hl("HttpPane" .. method, { fg = fg })
  end
  hl("HttpPaneOther", { fg = "#8a949c" })
  hl("HttpPaneButtonNew", { fg = "#e8eaee", bg = "#2f6f4f", bold = true })
  hl("HttpPaneButtonCurl", { fg = "#e8eaee", bg = "#33507d", bold = true })
  hl("HttpPaneCount", { link = "NonText" })
end
set_highlights()
api.nvim_create_autocmd("ColorScheme", { callback = set_highlights })

-- ── the data ────────────────────────────────────────────────────────────────────────────────────
-- the requests of a file: from its buffer when it is loaded (unsaved edits count), else from disk
local function requests_of(path, loaded)
  local buf = loaded[path]
  local stamp, lines
  if buf then
    stamp = "b" .. api.nvim_buf_get_changedtick(buf)
  else
    local stat = uv.fs_stat(path)
    stamp = stat and (stat.mtime.sec .. "." .. stat.mtime.nsec .. ":" .. stat.size) or "none"
  end
  local entry = parsed[path]
  if entry and entry.stamp == stamp then
    return entry.requests
  end
  if buf then
    lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  elseif stamp ~= "none" then
    lines = vim.fn.readfile(path)
  else
    lines = {}
  end
  local requests = parse.parse(lines)
  parsed[path] = { stamp = stamp, requests = requests }
  return requests
end

local function loaded_buffers()
  local loaded = {}
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) then
      local name = api.nvim_buf_get_name(buf)
      if name:find("%.http$") or name:find("%.rest$") then
        loaded[vim.fs.normalize(name)] = buf
      end
    end
  end
  return loaded
end

local function sorted_keys(t)
  local keys = vim.tbl_keys(t)
  table.sort(keys)
  return keys
end

-- The rows: two buttons, then folders -> files -> requests (folders that hold nothing but one folder are
-- shown as one row "a/b/c", like the Explorer of VS Code).
local function rows()
  local dir = cwd()
  local list = files.cached(dir) or {}
  local loaded = loaded_buffers()
  local items = {
    { text = "New request", kind = "button", action = "new" },
    { text = "Request from clipboard curl", kind = "button", action = "curl" },
  }

  local root = { dirs = {}, files = {}, path = "" }
  for _, rel in ipairs(list) do
    local parts = vim.split(rel, "/", { plain = true })
    local node = root
    for i = 1, #parts - 1 do
      local name = parts[i]
      node.dirs[name] = node.dirs[name] or { dirs = {}, files = {}, path = (node.path ~= "" and node.path .. "/" or "") .. name }
      node = node.dirs[name]
    end
    node.files[#node.files + 1] = { name = parts[#parts], rel = rel }
  end

  local function emit(node, parent)
    local entries = {}
    for _, name in ipairs(sorted_keys(node.dirs)) do
      local child, label = node.dirs[name], name
      while next(child.files) == nil and vim.tbl_count(child.dirs) == 1 do
        local only = next(child.dirs)
        label = label .. "/" .. only
        child = child.dirs[only]
      end
      entries[#entries + 1] = { kind = "dir", node = child, label = label }
    end
    table.sort(node.files, function(a, b)
      return a.name < b.name
    end)
    for _, file in ipairs(node.files) do
      entries[#entries + 1] = { kind = "file", file = file }
    end
    for i, entry in ipairs(entries) do
      local last = i == #entries
      if entry.kind == "dir" then
        local key = "d:" .. entry.node.path
        local item = {
          text = entry.label, kind = "dir", key = key, parent = parent, last = last,
          open = not collapsed[key], dirpath = dir .. "/" .. entry.node.path,
        }
        items[#items + 1] = item
        if item.open then
          emit(entry.node, item)
        end
      else
        local abs = dir .. "/" .. entry.file.rel
        local requests = requests_of(abs, loaded)
        local key = "f:" .. entry.file.rel
        local item = {
          text = entry.file.name, kind = "file", key = key, parent = parent, last = last, file = abs,
          open = not collapsed[key], count = #requests,
        }
        items[#items + 1] = item
        if item.open then
          for j, req in ipairs(requests) do
            items[#items + 1] = {
              text = req.name .. " " .. req.method .. " " .. req.url, kind = "request", file = abs, req = req,
              parent = item, last = j == #requests, key = "r:" .. entry.file.rel .. ":" .. req.line,
            }
          end
        end
      end
    end
  end
  emit(root, nil)
  return items
end

-- ── how a row looks ─────────────────────────────────────────────────────────────────────────────
local pad = kit.pad

local function format(item, picker)
  local ret = {}
  if item.kind == "button" then
    local new = item.action == "new"
    ret[#ret + 1] = { pad(new and "  ＋  New request" or "  ⎘  Request from clipboard curl", 38), new and "HttpPaneButtonNew" or "HttpPaneButtonCurl" }
    return ret
  end
  vim.list_extend(ret, Snacks.picker.format.tree(item, picker))
  local icons = picker.opts.icons.files
  if item.kind == "dir" then
    ret[#ret + 1] = { (item.open and icons.dir_open or icons.dir) .. " ", "SnacksPickerDirectory" }
    -- a long chain of folders ("a/b/c/d") keeps its end, where the folder that matters is
    local label, room = item.text, 36
    local depth = 0
    local node = item.parent
    while node do
      depth, node = depth + 1, node.parent
    end
    room = room - 2 * depth
    if vim.fn.strchars(label) > room then
      label = "…" .. vim.fn.strcharpart(label, vim.fn.strchars(label) - room + 1)
    end
    ret[#ret + 1] = { label, "SnacksPickerDirectory" }
  elseif item.kind == "file" then
    local icon, hl = Snacks.util.icon(item.text, "file")
    ret[#ret + 1] = { (icon or "") .. " ", hl }
    ret[#ret + 1] = { item.text, "SnacksPickerFile" }
    ret[#ret + 1] = { "  " .. item.count, "HttpPaneCount" }
  else
    local method = item.req.method
    local group = "HttpPane" .. (vim.fn.hlexists("HttpPane" .. method) == 1 and method or "Other")
    ret[#ret + 1] = { " " .. method .. " ", group }
    -- only the name; a request without one is known by its URL
    ret[#ret + 1] = { item.req.name == method .. " " .. item.req.url and item.req.url or item.req.name }
  end
  return ret
end

-- ── actions ─────────────────────────────────────────────────────────────────────────────────────
local function refresh(picker, keep_key)
  if not picker or picker.closed then
    return
  end
  picker:find({
    on_done = function()
      if not keep_key or picker.closed then
        return
      end
      for index, item in ipairs(picker:items()) do
        if item.key == keep_key then
          picker.list:move(index, true)
          return
        end
      end
    end,
  })
end

local function refresh_all(keep)
  for _, picker in ipairs(M.panes()) do
    refresh(picker, keep)
  end
end

-- go to `line` of `file` in the editing window (never over a diff)
local function goto_line(picker, file, line)
  last_file = vim.fs.normalize(file)
  return kit.goto_line(picker, file, line)
end

-- run the request under the cursor of the current buffer the way <CR> does in an .http file
-- (ftplugin/http.lua: Kulala with the progress spinner)
local function run_here()
  local map = vim.fn.maparg("<CR>", "n", false, true)
  if map.callback then
    map.callback()
  else
    vim.notify("This buffer has no request runner (is it an .http file?)", vim.log.levels.WARN, { title = "HTTP Requests" })
  end
end

local function toggle(picker, item)
  if item.open then
    collapsed[item.key] = true
  else
    collapsed[item.key] = nil
  end
  refresh(picker, item.key)
end

local move_to = kit.move_to

-- l: open a closed folder/file; on an open one go to its first row
local function open_node(picker, item)
  if not item or (item.kind ~= "dir" and item.kind ~= "file") then
    return
  end
  if not item.open then
    collapsed[item.key] = nil
    refresh(picker, item.key)
  else
    local items = picker:items()
    for index, candidate in ipairs(items) do
      if candidate.key == item.key and items[index + 1] and items[index + 1].parent == item then
        picker.list:move(index + 1, true)
        return
      end
    end
  end
end

-- h: close an open folder/file; on anything else go to the folder/file it is in
local function close_node(picker, item)
  if not item then
    return
  end
  if (item.kind == "dir" or item.kind == "file") and item.open then
    collapsed[item.key] = true
    refresh(picker, item.key)
  elseif item.parent and item.parent.key then
    move_to(picker, item.parent.key)
  end
end

local function is_http(name)
  return name:find("%.http$") ~= nil or name:find("%.rest$") ~= nil
end

-- The file new requests go to: the file under the cursor (a request counts as its file). For a button it is
-- the .http file shown in the editing window, else the last one gone to from the pane. For a folder (or
-- when there is no such file) a new file is asked for.
local function with_target(picker, item, fn)
  if item and (item.kind == "request" or item.kind == "file") then
    return fn(item.file)
  end
  if not item or item.kind == "button" then
    local win = picker.main
    local shown = win and api.nvim_win_is_valid(win) and vim.fs.normalize(api.nvim_buf_get_name(api.nvim_win_get_buf(win))) or ""
    if shown ~= "" and is_http(shown) then
      return fn(shown)
    end
    if last_file and uv.fs_stat(last_file) then
      return fn(last_file)
    end
  end
  local base = item and item.kind == "dir" and item.dirpath or cwd()
  local shown = vim.fn.fnamemodify(base, ":~:.")
  vim.ui.input({ prompt = "New .http file in " .. (shown == "" and "." or shown) .. "/ : " }, function(name)
    name = vim.trim(name or "")
    if name == "" then
      return
    end
    if not name:find("%.%w+$") then
      name = name .. ".http"
    end
    fn(base .. "/" .. name)
  end)
end

local function add_request(picker, item)
  with_target(picker, item, function(file)
    local _, line = edit.append(file, edit.NEW_REQUEST)
    refresh_all()
    if goto_line(picker, file, line) then
      vim.cmd("startinsert!")
    end
  end)
end

--- The text of the system clipboard (a seam: the tests replace it, they must never read the real one).
function M.clipboard()
  return vim.fn.getreg("+")
end

local function add_from_curl(picker, item)
  local lines, err = curl.to_lines(M.clipboard())
  if not lines then
    vim.notify(err, vim.log.levels.WARN, { title = "HTTP Requests" })
    return
  end
  with_target(picker, item, function(file)
    local _, line = edit.append(file, lines)
    refresh_all()
    goto_line(picker, file, line)
  end)
end

local BUTTONS = { new = add_request, curl = add_from_curl }

local actions = {
  -- Enter, double click, single click on a row
  http_confirm = function(picker, item)
    item = item or picker:current()
    if not item then
      return
    end
    if item.kind == "button" then
      BUTTONS[item.action](picker, nil)
    elseif item.kind == "request" then
      goto_line(picker, item.file, item.req.line)
    else
      toggle(picker, item)
    end
  end,
  http_run = function(picker, item)
    item = item or picker:current()
    if item and item.kind == "request" and goto_line(picker, item.file, item.req.line) then
      run_here()
    end
  end,
  http_new = function(picker, item)
    add_request(picker, item or picker:current())
  end,
  http_curl = function(picker, item)
    add_from_curl(picker, item or picker:current())
  end,
  http_open = function(picker, item)
    open_node(picker, item or picker:current())
  end,
  http_close = function(picker, item)
    close_node(picker, item or picker:current())
  end,
  http_refresh = function(picker)
    files.scan(cwd(), function()
      refresh(picker)
    end)
  end,
  http_press = kit.press,
  http_click = function(picker)
    kit.click(picker, "http_confirm")
  end,
}

-- ── the pane ────────────────────────────────────────────────────────────────────────────────────
local TITLE = "HTTP Requests"
kit.register(SOURCE, TITLE)

local function set_title(picker)
  kit.set_title(picker, TITLE)
end

--- The open panes of a tab (the current one by default).
function M.panes(tab)
  return kit.panes(SOURCE, tab)
end

local function open()
  -- nothing else may be a sidebar while this one is created (see core/sidebars.lua)
  require("core.sidebars").make_room_for_http()
  return Snacks.picker.pick({
    source = SOURCE,
    title = "", -- the title is the winbar (set_title); the search box must not repeat it
    finder = rows,
    format = format,
    tree = true,
    show_empty = true,
    focus = "list",
    auto_close = false,
    jump = { close = false },
    layout = { preset = "sidebar", preview = false, hidden = { "input" } },
    matcher = { sort_empty = false, fuzzy = false },
    sort = { fields = { "idx" } },
    confirm = "http_confirm",
    actions = actions,
    on_show = set_title,
    win = {
      list = {
        keys = vim.tbl_extend("error", kit.mouse_keys("http_press", "http_click"), {
          ["<CR>"] = "http_confirm",
          ["l"] = "http_open",
          ["h"] = "http_close",
          ["<C-CR>"] = "http_run",
          ["r"] = "http_run",
          ["a"] = "http_new",
          ["P"] = "http_curl",
          ["R"] = "http_refresh",
          ["q"] = "close",
          ["<Esc>"] = "close",
        }),
      },
    },
  })
end

--- <leader>h: show the pane; focus it when it is open elsewhere; close it when it has the focus.
function M.toggle()
  local panes = M.panes()
  if #panes > 0 then
    local current = api.nvim_get_current_win()
    for _, picker in ipairs(panes) do
      local win = picker.list.win.win
      if win == current then
        picker:close()
      else
        picker:focus("list")
      end
    end
    return
  end
  if vim.fn.executable("fd") == 0 then
    vim.notify("fd is not installed (brew install fd)", vim.log.levels.WARN)
    return
  end
  local dir = cwd()
  if files.cached(dir) then
    open()
    -- bring the list up to date; the pane follows when a file was added, moved or removed
    files.scan(dir, function(changed)
      if changed then
        refresh_all()
      end
    end)
  else
    files.scan(dir, open) -- never listed: list it first (a few tens of ms)
  end
end

--- Cmd+B: show the pane, or hide it whatever has the focus.
function M.show_hide()
  local panes = M.panes()
  if #panes > 0 then
    for _, picker in ipairs(panes) do
      picker:close()
    end
  else
    M.toggle()
  end
end

-- keep the pane current while .http files are edited
local group = api.nvim_create_augroup("HttpRequestsPane", { clear = true })
local timer
local function refresh_soon()
  if #M.panes() == 0 then
    return
  end
  timer = timer or assert(uv.new_timer())
  timer:stop()
  timer:start(150, 0, vim.schedule_wrap(function()
    refresh_all()
  end))
end
api.nvim_create_autocmd({ "BufWritePost", "TextChanged", "TextChangedI", "BufDelete", "DirChanged" }, {
  group = group,
  callback = function(args)
    local name = args.event == "DirChanged" and ".http" or (args.file or "")
    if name:find("%.http$") or name:find("%.rest$") then
      refresh_soon()
    end
  end,
})
vim.keymap.set("n", "<leader>h", M.toggle, { desc = "HTTP requests pane" })
vim.keymap.set("n", "<D-S-h>", M.toggle, { desc = "HTTP requests pane" })

return M
