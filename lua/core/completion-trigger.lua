-- Buffered/relayed insertion can change text without InsertCharPre. Blink's
-- normal typing listener then has no character to trigger on until InsertEnter.
--
-- Blink finishes its setup (its trigger listeners, the sources) only after an asynchronous check of its
-- fuzzy library, which takes a moment after startup, longer on a busy machine. A trigger character typed
-- before that would open nothing (and a context made then would look already requested): the check waits
-- for blink and then looks at the cursor again.
local M = {}

-- (never loads anything itself: a require here could start blink's whole setup in the middle of a key)
local function blink_ready()
  local trigger = package.loaded["blink.cmp.completion.trigger"]
  return type(trigger) == "table"
    and trigger.show_emitter ~= nil
    and #trigger.show_emitter.listeners > 0
end

local waiting = false
local function when_ready(fn)
  if waiting then
    return
  end
  waiting = true
  local timer = assert(vim.uv.new_timer())
  local deadline = vim.uv.now() + 15000
  timer:start(
    20,
    20,
    vim.schedule_wrap(function()
      if blink_ready() or vim.uv.now() > deadline then
        timer:stop()
        timer:close()
        waiting = false
        if blink_ready() then
          fn()
        end
      end
    end)
  )
end

-- open the menu for the character before the cursor of `buf`, when it is a trigger or keyword character
-- (`fresh`: blink just became ready, a context made before that was never requested)
local function check(buf, fresh)
  if vim.api.nvim_get_current_buf() ~= buf or vim.fn.mode() ~= "i" then
    return
  end
  local config = require("blink.cmp.config")
  if
    not config.enabled()
    or config.completion.menu.auto_show == false
    or #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/completion" }) == 0
  then
    return
  end
  local trigger = require("blink.cmp.completion.trigger")
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  if cursor[2] == 0 then
    return
  end
  local ctx = trigger.context
  -- Native typing already requested this exact context: do not duplicate
  -- or cancel its in-flight LSP request.
  if
    not fresh
    and ctx
    and ctx.bufnr == buf
    and vim.deep_equal(ctx.cursor, cursor)
    and ctx.line == line
  then
    return
  end
  local char =
    vim.fn.strcharpart(line:sub(1, cursor[2]), vim.fn.strchars(line:sub(1, cursor[2])) - 1, 1)
  if config.completion.trigger.show_on_trigger_character and trigger.is_trigger_character(char) then
    trigger.show({ trigger_kind = "trigger_character", trigger_character = char, force = fresh })
  elseif
    config.completion.trigger.show_on_keyword
    and require("blink.cmp.fuzzy").is_keyword_character(char)
  then
    trigger.show({ trigger_kind = "keyword", force = fresh })
  end
end

function M.setup()
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
    group = vim.api.nvim_create_augroup("CompletionTextTrigger", { clear = true }),
    callback = function(ev)
      local buf = ev.buf
      local tick = vim.api.nvim_buf_get_changedtick(buf)
      vim.schedule(function()
        -- only a buffer completion can open in: the current one (a prompt closed meanwhile is gone: asking
        -- its changedtick would raise an error), unchanged since, in Insert mode, with an LSP that completes
        if
          vim.api.nvim_get_current_buf() ~= buf
          or vim.api.nvim_buf_get_changedtick(buf) ~= tick
          or vim.fn.mode() ~= "i"
          or #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/completion" }) == 0
          or not package.loaded["blink.cmp"]
        then
          return
        end
        if not blink_ready() then
          return when_ready(function()
            check(buf, true)
          end)
        end
        check(buf)
      end)
    end,
  })
end

return M
