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
  end,
}
