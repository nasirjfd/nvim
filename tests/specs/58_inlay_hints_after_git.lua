local lib = require("lib")
local h = require("support")

-- A fake language server with inlay hints attaches to text files: one hint before "value".
-- The Git view used to save the hint setting before the server attached ("off") and put that
-- back when it let go of the file, so the hints never came back.
local function editor()
  local lines = {}
  for i = 1, 20 do
    lines[i] = "line " .. i
  end
  lines[5] = "call(value)"
  local dir = h.repo({ ["a.php.txt"] = lines, ["b.txt"] = { "other" } })
  lines[12] = "changed"
  h.write(dir .. "/a.php.txt", lines)
  h.write(dir .. "/b.txt", { "other", "more" })
  local screen = h.nvim(dir, 160, 40)
  screen:exec([[
    vim.api.nvim_create_autocmd('FileType', { pattern = 'text', callback = function(ev)
      vim.lsp.start({
        name = 'hint-test', root_dir = vim.fn.getcwd(),
        cmd = function(dispatchers)
          local closing, id = false, 0
          return {
            request = function(method, params, callback)
              id = id + 1
              local result
              if method == 'initialize' then
                result = { capabilities = { inlayHintProvider = true, textDocumentSync = 1 } }
              elseif method == 'textDocument/inlayHint' then
                result = { { position = { line = 4, character = 5 }, label = 'HINTPARAM:', kind = 2 } }
              end
              -- A real server (intelephense) attaches well after the diff has shown the file.
              vim.defer_fn(function() callback(nil, result) end, method == 'initialize' and 400 or 0)
              return true, id
            end,
            notify = function() return true end,
            is_closing = function() return closing end,
            terminate = function() closing = true; dispatchers.on_exit(0, 0) end,
          }
        end,
      }, { bufnr = ev.buf })
    end })
  ]])
  return screen
end

local function show_in_git(screen)
  screen:exec("vim.cmd('CodeDiff scm')")
  h.wait(screen, function()
    return screen:exec([[
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      if not p or not p.tree then return false end
      for line = 1, vim.api.nvim_buf_line_count(p.bufnr) do
        local node = p.tree:get_node(line)
        if node and node.data and node.data.path == 'a.php.txt' then
          p.on_file_select(node.data)
          return true
        end
      end
      return false
    ]])
  end, "changed file did not appear in Git")
  h.wait(screen, function()
    return screen:exec([[
      local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
      if not s or not s.stored_diff_result or not s.modified_bufnr then return false end
      if s.refresh and (s.refresh.loading or s.refresh.running) then return false end
      return #vim.lsp.get_clients({ bufnr = s.modified_bufnr, name = 'hint-test' }) == 1
    ]])
  end, "the diff did not load with the language server attached")
end

local exits = {
  ["the Git view is quit"] = function(screen)
    screen:exec("vim.cmd('tabonly'); require('codediff.ui.lifecycle').cleanup(vim.api.nvim_get_current_tabpage())")
  end,
  ["another file is opened from the Git pane"] = function(screen)
    screen:exec([[
      local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
      for line = 1, vim.api.nvim_buf_line_count(p.bufnr) do
        local node = p.tree:get_node(line)
        if node and node.data and node.data.path == 'b.txt' then
          vim.api.nvim_win_set_cursor(p.winid, { line, 0 })
          return p.on_file_select(node.data)
        end
      end
    ]])
  end,
}

for name, leave in pairs(exits) do
  lib.test("inlay hints show on a file first shown in Git once " .. name, function()
    local screen = editor()
    show_in_git(screen)
    leave(screen)
    h.wait(screen, function()
      return screen:exec([[
        local buf = vim.fn.bufnr('a.php.txt')
        for _, s in pairs(require('codediff.ui.lifecycle.session').get_active_diffs()) do
          if s.original_bufnr == buf or s.modified_bufnr == buf then return false end
        end
        return true
      ]])
    end, "the Git view still shows the file")
    screen:exec("vim.cmd('tabnew a.php.txt'); vim.api.nvim_win_set_cursor(0, {12, 0})")
    h.wait(screen, function()
      return h.find_on_screen(screen, "HINTPARAM:") ~= nil
    end, "the inlay hint is not drawn")
    screen:close()
  end)
end

lib.test("inlay hints stay on a file while a Git view shows it, in the diff and in another tab", function()
  local screen = editor()
  show_in_git(screen)
  -- the diff pane itself
  h.wait(screen, function()
    return h.find_on_screen(screen, "HINTPARAM:") ~= nil
  end, "the inlay hint is not drawn in the diff")
  -- the same buffer in a normal window of another tab, while the Git view still holds it
  screen:exec("vim.cmd('tabnew a.php.txt'); vim.api.nvim_win_set_cursor(0, {12, 0})")
  h.wait(screen, function()
    return h.find_on_screen(screen, "HINTPARAM:") ~= nil
  end, "the inlay hint is not drawn in another tab while the Git view holds the file")
  lib.ok(screen:exec("return vim.lsp.inlay_hint.is_enabled({ bufnr = vim.fn.bufnr('a.php.txt') })"), "hints were turned off")
  screen:close()
end)
