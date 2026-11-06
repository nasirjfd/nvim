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
