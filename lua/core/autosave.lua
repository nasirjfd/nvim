local M = {}

function M.save(buf)
  if not vim.g.autosave or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end
  local opts = vim.bo[buf]
  if
    opts.buftype ~= ""
    or not opts.modifiable
    or opts.readonly
    or not opts.modified
    or vim.api.nvim_buf_get_name(buf) == ""
  then
    return
  end
  local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
    vim.cmd("silent update")
  end)
  if not ok then
    vim.notify("Autosave failed: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.flush()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    M.save(buf)
  end
end

function M.setup()
  vim.g.autosave = true
  local group = vim.api.nvim_create_augroup("Autosave", { clear = true })
  vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave", "FocusLost" }, {
    group = group,
    callback = function(ev)
      M.save(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffSCMPreOpen",
    callback = M.flush,
  })
end

return M
