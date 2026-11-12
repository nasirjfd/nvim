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
local hidden = require("modules.http_requests.hidden")
local pinned = require("modules.http_requests.pinned")

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
  hl("HttpPaneIconNew", { fg = "#7fa585" })
  hl("HttpPaneIconCurl", { fg = "#7d9bbf" })
  hl("HttpPaneIconHidden", { fg = "#b59a72" })
  hl("HttpPaneIconHiddenOn", { fg = "#e0c08a", bold = true })
  hl("HttpPaneHiddenDir", { link = "Comment" })
  hl("HttpPaneDim", { link = "Comment" })
  hl("HttpPanePin", { fg = "#e0c08a" })
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
  -- the toolbar: new request, request from the clipboard curl, the hidden folders (their number)
  local toolbar = { text = "Toolbar", kind = "button", toolbar = true, hidden_count = 0, showing = hidden.showing(), key = "h:toolbar" }
  local items = { toolbar }
  local hidden_set = hidden.set(dir)

  local pins = pinned.list(dir)
  local pin_header
  if #pins > 0 then
    pin_header = { text = "Pinned", kind = "section", key = "pin:header", last = false, open = true }
    items[#items + 1] = pin_header
  end

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

  local function emit(node, parent, dim)
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
        local is_hidden = hidden_set[entry.node.path] == true
        if is_hidden then
          toolbar.hidden_count = toolbar.hidden_count + 1
        end
        if not is_hidden or toolbar.showing then
          local item = {
            text = entry.label, kind = "dir", key = key, parent = parent, last = last,
            open = not collapsed[key], dirpath = dir .. "/" .. entry.node.path,
            relpath = entry.node.path, hidden = is_hidden, dim = dim or is_hidden,
          }
          items[#items + 1] = item
          if item.open then
            emit(entry.node, item, item.dim)
          end
        end
      else
        local abs = dir .. "/" .. entry.file.rel
        local requests = requests_of(abs, loaded) -- a pinned request stays here too (and is marked)
        local key = "f:" .. entry.file.rel
        local item = {
          text = entry.file.name, kind = "file", key = key, parent = parent, last = last, file = abs,
          open = not collapsed[key], count = #requests, dim = dim,
        }
        items[#items + 1] = item
        if item.open then
          for j, req in ipairs(requests) do
            items[#items + 1] = {
              text = req.name .. " " .. req.method .. " " .. req.url, kind = "request", file = abs, req = req,
              parent = item, last = j == #requests, key = "r:" .. entry.file.rel .. ":" .. req.line,
              rel = entry.file.rel, dim = dim, pinned = pinned.is_pinned(dir, entry.file.rel, req),
            }
          end
        end
      end
    end
  end
  -- the pinned requests (looked up in their files; one that is gone is left out)
  if pin_header then
    local count = 0
    for _, pin in ipairs(pins) do
      local abs = dir .. "/" .. pin.file
      for _, req in ipairs(requests_of(abs, loaded)) do
        if req.method == pin.method and req.url == pin.url and req.name == pin.name then
          count = count + 1
          if pin_header.open then
            items[#items + 1] = {
              text = req.name .. " " .. req.method .. " " .. req.url, kind = "request", file = abs, req = req,
              parent = pin_header, last = false, key = "p:" .. pin.file .. ":" .. req.line, rel = pin.file,
              in_pins = true,
            }
          end
          break
        end
      end
    end
    pin_header.count = count
    if pin_header.open then
      local last = items[#items]
      if last.in_pins then
        last.last = true
      end
    end
  end
  emit(root, nil)
  return items
end

-- ── how a row looks ─────────────────────────────────────────────────────────────────────────────
local pad = kit.pad

-- The toolbar row is only icons: new request, request from the clipboard curl, the hidden folders (and how many).
-- The same table draws the row and tells what a click at a column hit.
function M.toolbar_parts(item)
  local count = item.hidden_count or 0
  local parts = {
    { text = "  ", hl = "HttpPaneCount" },
    { text = "󰐕 ", hl = "HttpPaneIconNew", zone = "new" },
    { text = "  ", hl = "HttpPaneCount" },
    { text = "󰅍 ", hl = "HttpPaneIconCurl", zone = "curl" },
    { text = "  ", hl = "HttpPaneCount" },
    { text = (item.showing and "󰈈 " or "󰈉 ") .. count, hl = item.showing and "HttpPaneIconHiddenOn" or "HttpPaneIconHidden", zone = "hidden" },
  }
  local col = 1
  for _, part in ipairs(parts) do
    part.from, part.to = col, col + vim.fn.strdisplaywidth(part.text) - 1
    col = part.to + 1
  end
  return parts
end

local function toolbar_zone(item, col)
  for _, part in ipairs(M.toolbar_parts(item)) do
    if part.zone and col >= part.from and col <= part.to then
      return part.zone
    end
  end
end

local function format(item, picker)
  local ret = {}
  if item.kind == "button" then
    for _, part in ipairs(M.toolbar_parts(item)) do
      ret[#ret + 1] = { part.text, part.hl }
    end
    return ret
  end
  if item.kind == "section" then -- a label, not a folder: no fold arrow, nothing to open
    return {
      { " 󰐃 ", "HttpPanePin" },
      { "Pinned", "SnacksPickerDirectory" },
      { "  " .. (item.count or 0), "HttpPaneCount" },
    }
  end
  vim.list_extend(ret, Snacks.picker.format.tree(item, picker))
  local icons = picker.opts.icons.files
  if item.kind == "dir" then
    ret[#ret + 1] = { (item.open and icons.dir_open or icons.dir) .. " ", item.dim and "HttpPaneHiddenDir" or "SnacksPickerDirectory" }
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
    ret[#ret + 1] = { label, item.dim and "HttpPaneHiddenDir" or "SnacksPickerDirectory" }
    if item.hidden then
      ret[#ret + 1] = { "  󰈉", "HttpPaneIconHidden" }
    end
  elseif item.kind == "file" then
    local icon, hl = Snacks.util.icon(item.text, "file")
    ret[#ret + 1] = { (icon or "") .. " ", item.dim and "HttpPaneDim" or hl }
    ret[#ret + 1] = { item.text, item.dim and "HttpPaneDim" or "SnacksPickerFile" }
    ret[#ret + 1] = { "  " .. item.count, "HttpPaneCount" }
  else
    local method = item.req.method
    local group = item.dim and "HttpPaneDim" or "HttpPane" .. (vim.fn.hlexists("HttpPane" .. method) == 1 and method or "Other")
    ret[#ret + 1] = { " " .. method .. " ", group }
    -- only the name; a request without one is known by its URL
    ret[#ret + 1] = { item.req.name == method .. " " .. item.req.url and item.req.url or item.req.name, item.dim and "HttpPaneDim" or nil }
    if item.in_pins then
      ret[#ret + 1] = { "  " .. vim.fn.fnamemodify(item.rel, ":t"), "HttpPaneCount" }
    elseif item.pinned then
      ret[#ret + 1] = { " 󰐃", "HttpPanePin" }
    end
  end
  return ret
end

-- ── actions ─────────────────────────────────────────────────────────────────────────────────────
local refresh = kit.refresh

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

local actions = {
  -- Enter, double click, single click on a row
  http_confirm = function(picker, item)
    item = item or picker:current()
    if not item then
      return
    end
    if item.kind == "button" or item.kind == "section" then
      return -- the toolbar acts on clicks (http_click) and on its keys
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
    local mouse = vim.fn.getmousepos()
    local list_win = picker.list and picker.list.win and picker.list.win.win
    if mouse.winid ~= list_win then
      return
    end
    vim.schedule(function()
      if picker.closed then
        return
      end
      local item = picker:current()
      if item and item.kind == "button" then
        local zone = toolbar_zone(item, mouse.wincol)
        if zone == "new" then
          picker:action("http_new")
        elseif zone == "curl" then
          picker:action("http_curl")
        elseif zone == "hidden" then
          picker:action("http_show_hidden")
        end
        return
      end
      picker:action("http_confirm")
    end)
  end,
  -- hide the folder under the cursor (or show it again when it is hidden); kept between sessions
  http_hide = function(picker, item)
    item = item or picker:current()
    if item and item.kind == "dir" and item.relpath then
      hidden.toggle(cwd(), item.relpath)
      refresh(picker)
    end
  end,
  -- pin the request under the cursor to the top of the pane (or unpin it)
  http_pin = function(picker, item)
    item = item or picker:current()
    if item and item.kind == "request" and item.rel then
      pinned.toggle(cwd(), item.rel, item.req)
      refresh(picker)
    end
  end,
  -- a small window with the keys of the pane
  http_help = function()
    local lines = {
      " HTTP pane keys",
      "",
      " Enter / click   go to the request",
      " r  Ctrl+Enter   run request",
      " a               new request",
      " P               request from clipboard curl",
      " p               pin / unpin request",
      " x               hide / unhide folder",
      " H               show hidden folders",
      " l / h           open / close",
      " R               refresh",
      " q  Esc          close",
      " ?               this help",
    }
    Snacks.win({
      text = lines,
      width = 40,
      height = #lines,
      border = "rounded",
      backdrop = false,
      wo = { wrap = false },
      bo = { modifiable = false },
      keys = { q = "close", ["<Esc>"] = "close", ["?"] = "close" },
    })
  end,
  -- show the hidden folders (dimmed) or not
  http_show_hidden = function(picker)
    hidden.toggle_show()
    refresh(picker, "h:toolbar")
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
          ["x"] = "http_hide",
          ["p"] = "http_pin",
          ["H"] = "http_show_hidden",
          ["P"] = "http_curl",
          ["R"] = "http_refresh",
          ["?"] = "http_help",
          ["q"] = "close",
          ["<Esc>"] = "close",
        }),
      },
    },
  })
end

--- <leader>h: show the pane and put the cursor in it; it never closes it (Cmd+B and q do).
function M.toggle()
  local panes = M.panes()
  if #panes > 0 then
    panes[1]:focus("list")
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
