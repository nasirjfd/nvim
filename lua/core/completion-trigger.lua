-- Buffered/relayed insertion can change text without InsertCharPre. Blink's
-- normal typing listener then has no character to trigger on until InsertEnter.
local M = {}

function M.setup()
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
    group = vim.api.nvim_create_augroup("CompletionTextTrigger", { clear = true }),
    callback = function(ev)
      local tick = vim.api.nvim_buf_get_changedtick(ev.buf)
      vim.schedule(function()
        if
          vim.api.nvim_get_current_buf() ~= ev.buf
          or vim.fn.mode() ~= "i"
          or vim.api.nvim_buf_get_changedtick(ev.buf) ~= tick
        then
          return
        end
        local config = require("blink.cmp.config")
        if
          not config.enabled()
          or config.completion.menu.auto_show == false
          or #vim.lsp.get_clients({ bufnr = ev.buf, method = "textDocument/completion" }) == 0
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
          ctx
          and ctx.bufnr == ev.buf
          and vim.deep_equal(ctx.cursor, cursor)
          and ctx.line == line
        then
          return
        end
        local char =
          vim.fn.strcharpart(line:sub(1, cursor[2]), vim.fn.strchars(line:sub(1, cursor[2])) - 1, 1)
        if
          config.completion.trigger.show_on_trigger_character and trigger.is_trigger_character(char)
        then
          trigger.show({ trigger_kind = "trigger_character", trigger_character = char })
        elseif
          config.completion.trigger.show_on_keyword
          and require("blink.cmp.fuzzy").is_keyword_character(char)
        then
          trigger.show({ trigger_kind = "keyword" })
        end
      end)
    end,
  })
end

return M
