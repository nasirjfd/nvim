-- Native macOS navigation in single-line prompts, including Git commit messages.
local M = {}
local api = vim.api

function M.attach(buf, cancel)
  if not api.nvim_buf_is_valid(buf) or vim.b[buf].mac_input_navigation then
    return
  end
  vim.b[buf].mac_input_navigation = true
  require("core.input-text-selection").attach(buf)
  local function move(insert, normal)
    require("core.input-text-selection").clear(buf)
    local key = vim.fn.mode():sub(1, 1) == "i" and insert or normal
    api.nvim_feedkeys(vim.keycode(key), "in", false)
  end
  local function map(keys, insert, normal, desc)
    for _, key in ipairs(keys) do
      vim.keymap.set({ "i", "n" }, key, function()
        move(insert, normal)
      end, { buffer = buf, silent = true, desc = desc })
    end
  end
  -- No <Esc>b / <Esc>f mappings: with them Neovim held every Escape for 'timeoutlen' (1 s) waiting
  -- for the b/f. The Insert-mode Escape below catches a split Option+arrow itself.
  map({ "<M-Left>", "<M-b>" }, "<C-Left>", "b", "Previous Word")
  map({ "<M-Right>", "<M-f>" }, "<C-Right>", "w", "Next Word")
  map({ "<D-Left>" }, "<Home>", "0", "Start of Line")
  map({ "<D-Right>" }, "<End>", "$", "End of Line")
  -- Keep the prompt's normal-mode cancellation ahead of the legacy prefixes.
  if cancel then
    vim.keymap.set("n", "<Esc>", vim.schedule_wrap(cancel), {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = "Cancel input",
    })
  end

  -- Some terminal relays split Option+arrow into Escape followed by b/f: give only that legacy
  -- sequence a short chance to complete. A lone Escape closes the prompt at once, like any dialog
  -- (it used to only leave Insert mode, and a second one closed it).
  vim.keymap.set("i", "<Esc>", function()
    vim.wait(100, function()
      return vim.fn.getchar(1) ~= 0
    end, 5)
    local next_key = vim.fn.getchar(1) ~= 0 and vim.fn.getchar(0) or nil
    if next_key == string.byte("b") or next_key == "b" then
      move("<C-Left>", "b")
    elseif next_key == string.byte("f") or next_key == "f" then
      move("<C-Right>", "w")
    else
      if cancel then
        vim.cmd.stopinsert()
        cancel()
      else
        vim.cmd.stopinsert()
      end
      if next_key then
        api.nvim_feedkeys(
          type(next_key) == "number" and vim.fn.nr2char(next_key) or next_key,
          "in",
          false
        )
      end
    end
  end, {
    buffer = buf,
    silent = true,
    nowait = true,
    desc = "Leave input mode (preserve Option arrows)",
  })
end

return M
