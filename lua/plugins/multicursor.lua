return {
  "jake-stewart/multicursor.nvim",
  branch = "1.0",
  config = function()
    local mc = require("multicursor-nvim")
    mc.setup()

    local set = vim.keymap.set

    set({ "n", "x" }, "<down>", function()
      mc.lineAddCursor(1)
    end)

    set({ "n", "x" }, "<up>", function()
      mc.lineAddCursor(-1)
    end)

    set({ "n", "x" }, "<leader>n", function()
      mc.matchAddCursor(1)
    end)

    set({ "n", "x" }, "<leader>s", function()
      mc.matchSkipCursor(1)
    end)

    set({ "n", "x" }, "<leader>N", function()
      mc.matchAddCursor(-1)
    end)

    set({ "n", "x" }, "<leader>S", function()
      mc.matchSkipCursor(-1)
    end)

    -- ctrl+g, like VS Code's "add next occurrence": the first press selects the word under the
    -- cursor, every next press adds a cursor (with its selection) on the next match of it
    set("n", "<C-g>", function()
      vim.cmd("normal! viw")
    end, { desc = "Select Word (ctrl+g again: next occurrence)" })
    set("x", "<C-g>", function()
      mc.matchAddCursor(1)
    end, { desc = "Add Cursor on Next Occurrence" })

    set("n", "<c-leftmouse>", mc.handleMouse)

    -- The popup of gh (LSP hover or line diagnostics) shown for the current buffer, or the one the
    -- cursor is in: Neovim records it as b:lsp_floating_preview of the buffer it was opened from.
    local function hover_popup()
      local current = vim.api.nvim_get_current_win()
      for _, buf in ipairs({ vim.api.nvim_get_current_buf(), unpack(vim.api.nvim_list_bufs()) }) do
        local win = vim.b[buf].lsp_floating_preview
        if win and vim.api.nvim_win_is_valid(win) and (buf == vim.api.nvim_get_current_buf() or win == current) then
          return win
        end
      end
    end

    -- Escape closes the gh popup first, then clears multiple cursors; falls through to normal
    -- <Esc> behavior (clear search highlight) when there is neither.
    set("n", "<esc>", function()
      local popup = hover_popup()
      if popup then
        vim.api.nvim_win_close(popup, true)
      elseif mc.hasCursors() then
        mc.clearCursors()
      else
        vim.cmd("nohlsearch")
      end
    end, { desc = "Close Popup / Clear Cursors / Highlight" })
  end,
}
