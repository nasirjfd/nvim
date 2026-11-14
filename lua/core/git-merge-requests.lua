local M = {}

local function run(root, args)
  local result = vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }):wait()
  return result.code == 0 and vim.trim(result.stdout) or ""
end

-- Match ggr's remote preference: the branch's upstream, then origin, then the first remote.
function M.url(root)
  local upstream = run(root, { "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" })
  local remote = upstream:match("^([^/]+)/")
  local remotes = vim.split(run(root, { "remote" }), "\n", { trimempty = true })
  if not remote or not vim.tbl_contains(remotes, remote) then
    remote = vim.tbl_contains(remotes, "origin") and "origin" or remotes[1]
  end
  if not remote then
    return nil, "This repository has no Git remote"
  end
  local actions = require("codediff.ui.explorer.actions")
  local url = actions.remote_web_url(run(root, { "remote", "get-url", remote }))
  if not url then
    return nil, "Cannot make a browser URL from the " .. remote .. " remote"
  end
  return url .. (url:match("^https://github%.com/") and "/pulls" or "/-/merge_requests")
end

function M.open()
  local panel = require("codediff.ui.lifecycle").get_panel_view(vim.api.nvim_get_current_tabpage())
  local actions = require("codediff.ui.explorer.actions")
  local root = panel and actions.root_of(panel, panel.tree and panel.tree:get_node())
  if not root then
    vim.notify(
      "Select a repository or file in the Git pane first",
      vim.log.levels.WARN,
      { title = "Merge Requests" }
    )
    return
  end
  local url, err = M.url(root)
  if url then
    local _, open_err = vim.ui.open(url)
    err = open_err
  end
  if err then
    vim.notify(tostring(err), vim.log.levels.WARN, { title = "Merge Requests" })
  end
end

return M
