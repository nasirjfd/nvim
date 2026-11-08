-- <leader>fj: a floating scratch window for JSON. Paste into it and it formats itself (jq).
-- The text stays there until you close Neovim, so reopening shows the last JSON.
local M = {}

local api = vim.api
local buf

local function format(win)
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  local text = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  if not text:find("%S") then
    return
  end
  local result = vim.system({ "jq", "--indent", "2", "." }, { stdin = text, text = true }):wait()
  local ok = result.code == 0 and result.stdout ~= ""
  if api.nvim_win_is_valid(win) then
    api.nvim_win_set_config(win, {
      footer = ok and " q close " or " not valid JSON yet · q close ",
      footer_pos = "right",
    })
  end
  if not ok then
    return
  end
  local lines = vim.split(vim.trim(result.stdout), "\n", { plain = true })
  if table.concat(lines, "\n") == vim.trim(text) then
    return
  end
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd.stopinsert()
  if api.nvim_win_is_valid(win) then
    api.nvim_win_set_cursor(win, { 1, 0 })
  end
end

function M.open()
  if vim.fn.executable("jq") == 0 then
    vim.notify("jq is not installed (brew install jq)", vim.log.levels.WARN)
    return
  end
  local fresh = not (buf and api.nvim_buf_is_valid(buf))
  if fresh then
    buf = api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].filetype = "json"
  end
  local width = math.floor(vim.o.columns * 0.7)
  local height = math.floor(vim.o.lines * 0.75)
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2) - 1,
    border = "rounded",
    title = " JSON · paste here, it formats itself ",
    title_pos = "center",
    footer = " q close ",
    footer_pos = "right",
  })
  vim.wo[win].wrap = false
  if fresh then
    local pending = false
    api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer = buf,
      callback = function()
        if pending then
          return
        end
        pending = true
        vim.schedule(function()
          pending = false
          format(api.nvim_get_current_win())
        end)
      end,
    })
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "Close JSON window" })
    vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, desc = "Close JSON window" })
  end
  if api.nvim_buf_line_count(buf) == 1 and api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "" then
    vim.cmd.startinsert()
  end
end

vim.keymap.set("n", "<leader>fj", M.open, { desc = "JSON formatter (paste to format)" })

return M
