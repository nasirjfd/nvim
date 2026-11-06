-- Send an @file#Lstart-end reference (like the VS Code Claude plugin) to the herdr pane labelled "claude".
local M = {}

local script = vim.fn.expand("~/.config/herdr/send-ref.sh")

function M.reference(l1, l2)
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then
    return nil
  end
  local path = vim.fn.fnamemodify(name, ":.")
  local ref = "@" .. path .. "#L" .. l1
  if l2 ~= l1 then
    ref = ref .. "-" .. l2
  end
  return ref
end

function M.send(visual)
  if not vim.env.HERDR_PANE_ID then
    vim.notify("Not running inside herdr", vim.log.levels.WARN)
    return
  end
  local l1, l2 = vim.fn.line("."), vim.fn.line(".")
  if visual then
    l1, l2 = vim.fn.line("v"), vim.fn.line(".")
    if l1 > l2 then
      l1, l2 = l2, l1
    end
  end
  local ref = M.reference(l1, l2)
  if not ref then
    vim.notify("Buffer has no file", vim.log.levels.WARN)
    return
  end
  vim.system({ script, ref .. " " }, { text = true }, function(res)
    vim.schedule(function()
      if res.code == 0 then
        vim.notify("Sent " .. ref, vim.log.levels.INFO)
      else
        vim.notify("herdr: " .. vim.trim(res.stderr or "failed"), vim.log.levels.ERROR)
      end
    end)
  end)
end

vim.keymap.set("n", "<leader>al", function()
  M.send(false)
end, { desc = "Send file#line ref to Claude (herdr)" })
vim.keymap.set("x", "<leader>al", function()
  M.send(true)
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
end, { desc = "Send file#lines ref to Claude (herdr)" })

return M
