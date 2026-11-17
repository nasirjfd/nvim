-- Send an @file#Lstart-end reference (like the VS Code Claude plugin) to the herdr pane labelled "claude".
local M = {}

local script = vim.fn.expand("~/.config/herdr/send-ref.sh")

function M.graph_reference()
  local graphs = package.loaded["codediff.ui.graph"]
  local graph = graphs and graphs.get(vim.api.nvim_get_current_tabpage())
  if not graph then
    return nil
  end
  local branches = graph.filters and graph.filters.branch
  local branch = branches and #branches > 0 and table.concat(branches, ", ") or nil
  if not branch then
    local result = vim
      .system({ "git", "-C", graph.root, "rev-parse", "--abbrev-ref", "HEAD" }, { text = true })
      :wait()
    if result.code ~= 0 then
      return nil
    end
    branch = vim.trim(result.stdout)
    if branch == "HEAD" then
      local head = vim
        .system({ "git", "-C", graph.root, "rev-parse", "--short", "HEAD" }, { text = true })
        :wait()
      branch = head.code == 0 and ("detached HEAD " .. vim.trim(head.stdout)) or branch
    end
  end
  return string.format("%s->branch:%s", graph.name or vim.fn.fnamemodify(graph.root, ":t"), branch)
end

function M.reference(l1, l2)
  local graph = M.graph_reference()
  if graph then
    return graph
  end
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
