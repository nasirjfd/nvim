-- Kulala keymaps, buffer-local to .http / .rest files only (nothing leaks into other filetypes)
local function k(lhs, fn, desc)
  vim.keymap.set("n", lhs, function()
    require("kulala")[fn]()
  end, { buffer = true, silent = true, desc = "Kulala: " .. desc })
end

-- Kulala only draws its ⏳ marker when the request finishes, so show our own spinner while the
-- request queue is busy.
local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local function with_progress(fn)
  return function()
    local db = require("kulala.db")
    local before = #db.global_update().responses
    require("kulala")[fn]()
    local started, frame = vim.uv.hrtime(), 0
    local timer = assert(vim.uv.new_timer())
    timer:start(
      0,
      100,
      vim.schedule_wrap(function()
        -- two ticks can be queued behind a blocked UI (a long message waiting for a key): the
        -- second one must not close the timer again
        if timer:is_closing() then
          return
        end
        local elapsed = (vim.uv.hrtime() - started) / 1e9
        local finished = #db.global_update().responses > before
        local busy = not finished and elapsed < 120
        if not busy then
          timer:stop()
          timer:close()
          vim.notify("", vim.log.levels.INFO, { id = "kulala_progress", timeout = 1 })
          return
        end
        frame = frame % #spinner + 1
        vim.notify(
          ("%.1fs"):format((vim.uv.hrtime() - started) / 1e9),
          vim.log.levels.INFO,
          { id = "kulala_progress", title = spinner[frame] .. " Sending request", timeout = false }
        )
      end)
    )
  end
end

local function send(lhs, fn, desc)
  vim.keymap.set("n", lhs, with_progress(fn), { buffer = true, silent = true, desc = "Kulala: " .. desc })
end

send("<CR>", "run", "Send request")
send("<leader><CR>", "run_all", "Send all requests")
send("<BS>", "replay", "Replay last request")
k("]r", "jump_next", "Next request")
k("[r", "jump_prev", "Previous request")
k("\\e", "set_selected_env", "Select environment")
k("\\i", "inspect", "Inspect request")
k("\\f", "search", "Find request")
k("\\c", "copy", "Copy as cURL")
k("\\C", "from_curl", "Paste cURL")
k("\\b", "scratchpad", "Scratchpad")
k("\\t", "toggle_view", "Toggle headers/body")
k("\\q", "close", "Close result")

-- gd on a {{variable}} goes to where it is defined. Kulala's built-in language server has no
-- "definition" handler, so gd did nothing here. A variable is defined by `@name = value` in the file,
-- by a request called `# @name name` (for {{name.response…}}), or by a key in the nearest
-- http-client.env.json / http-client.private.env.json (looked up from the file's folder upwards).
local function variable_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local from = 1
  while true do
    local s, e, inner = line:find("{{%s*(.-)%s*}}", from)
    if not s then
      return nil
    end
    if col >= s and col <= e then
      return inner:match("^[%w_%-%$]+")
    end
    from = e + 1
  end
end

local function definitions(name)
  local found = {}
  local file = vim.api.nvim_buf_get_name(0)
  local escaped = vim.pesc(name)
  for index, text in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local at = text:find("^%s*@" .. escaped .. "%s*=")
    local request = text:find("^%s*[#/]+%s*@name%s+" .. escaped .. "%s*$")
    if at or request then
      table.insert(found, { file = file, lnum = index, col = (text:find("@", 1, true) or 1) - 1, label = text })
    end
  end
  if #found > 0 then
    return found
  end
  for _, env in ipairs({ "http-client.env.json", "http-client.private.env.json" }) do
    for _, path in ipairs(vim.fs.find(env, { path = vim.fs.dirname(file), upward = true, limit = math.huge })) do
      for index, text in ipairs(vim.fn.readfile(path)) do
        local s = text:find('"' .. escaped .. '"%s*:')
        if s then
          table.insert(found, { file = path, lnum = index, col = s, label = vim.fn.fnamemodify(path, ":t") .. ": " .. vim.trim(text) })
        end
      end
      if #found > 0 then
        return found
      end
    end
  end
  return found
end

local function jump(target)
  if vim.api.nvim_buf_get_name(0) ~= target.file then
    vim.cmd("edit " .. vim.fn.fnameescape(target.file))
  end
  vim.api.nvim_win_set_cursor(0, { target.lnum, target.col })
  vim.cmd("normal! zz")
end

vim.keymap.set("n", "gd", function()
  local name = variable_under_cursor()
  if not name then
    -- not on a variable: the usual gd
    for _, map in ipairs(vim.api.nvim_get_keymap("n")) do
      if map.lhs == "gd" and map.callback then
        return map.callback()
      end
    end
    return
  end
  local found = definitions(name)
  if #found == 0 then
    vim.notify(("No definition of {{%s}} (looked in this file and http-client.env.json)"):format(name), vim.log.levels.WARN)
  elseif #found == 1 then
    jump(found[1])
  else
    vim.ui.select(found, {
      prompt = "{{" .. name .. "}}",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if choice then
        jump(choice)
      end
    end)
  end
end, { buffer = true, silent = true, desc = "Go to variable definition" })

-- Fold by request: `zM` collapses every request to its name + method + URL, `zo` / `za` open one,
-- `zR` opens all. `\z` toggles between all collapsed and all open. Starts open.
vim.opt_local.foldmethod = "expr"
vim.opt_local.foldexpr = "v:lua.require'core.http-fold'.expr(v:lnum)"
vim.opt_local.foldtext = "v:lua.require'core.http-fold'.text()"
vim.opt_local.foldlevel = 99
vim.opt_local.foldenable = true
vim.opt_local.fillchars:append({ fold = " " })
vim.keymap.set("n", "\\z", function()
  if vim.wo.foldlevel == 0 then
    vim.cmd("normal! zR")
  else
    vim.cmd("normal! zM")
  end
end, { buffer = true, silent = true, desc = "Collapse / expand all requests" })
