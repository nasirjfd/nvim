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

    -- Escape clears multiple cursors first; falls through to normal <Esc>
    -- behavior (clear search highlight) when there are none.
    set("n", "<esc>", function()
      if mc.hasCursors() then
        mc.clearCursors()
      else
        vim.cmd("nohlsearch")
      end
    end, { desc = "Clear Cursors / Highlight" })
  end,
}
