-- One window-local name highlight, updated synchronously with the pane selection.
local M = {}
local api = vim.api
local states = setmetatable({}, { __mode = "k" })

function M.clear(picker)
  local old = states[picker]
  if old and api.nvim_win_is_valid(old.win) then
    pcall(vim.fn.matchdelete, old.match, old.win)
  end
  states[picker] = nil
end

function M.show(picker, item)
  local win = require("modules.pane_kit").editing_window(picker)
  if not (win and api.nvim_win_is_valid(win)) then
    return
  end
  local req, file = item.req, item.file
  local buf = api.nvim_win_get_buf(win)
  local key = file .. ":" .. req.line .. ":" .. api.nvim_buf_get_changedtick(buf)
  local old = states[picker]
  if old and old.win == win and old.buf == buf and old.key == key then
    if not vim.treesitter.highlighter.active[buf] then
      require("core.http-highlight").ensure(buf)
    end
    return
  end
  M.clear(picker)
  api.nvim_win_call(win, function()
    local changed = vim.fs.normalize(api.nvim_buf_get_name(0)) ~= vim.fs.normalize(file)
    if changed then
      vim.cmd("edit " .. vim.fn.fnameescape(file))
    end
    buf = api.nvim_get_current_buf()
    if changed or not vim.treesitter.highlighter.active[buf] then
      require("core.http-highlight").ensure(buf)
    end
    if
      (changed or not old)
      and vim.bo.filetype == "http"
      and not vim.fn.maparg("<CR>", "n", false, true).callback
    then
      vim.cmd("runtime! ftplugin/http.lua")
    end
    api.nvim_win_set_cursor(win, { math.min(req.line, api.nvim_buf_line_count(buf)), 0 })
    if vim.fn.foldclosed(req.line) ~= -1 then
      vim.cmd("normal! zv")
    end
    -- Do not recenter/recompute the entire folded viewport on every j/k.
    if req.name_line < vim.fn.line("w0") or req.line > vim.fn.line("w$") then
      vim.cmd("normal! zz")
    end
  end)
  local match = vim.fn.matchaddpos("HttpRequestSelectedName", {
    { req.name_line, req.name_col + 1, math.max(1, req.name_end - req.name_col) },
  }, 200, -1, { window = win })
  states[picker] = {
    win = win,
    buf = buf,
    key = file .. ":" .. req.line .. ":" .. api.nvim_buf_get_changedtick(buf),
    match = match,
  }
end

return M
