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
