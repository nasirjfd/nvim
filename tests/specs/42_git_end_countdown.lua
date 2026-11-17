local lib = require("lib")
local h = require("support")

for _, mode in ipairs({ "Git pane", "commit page" }) do
  for _, kind in ipairs({ "modified", "added", "deleted" }) do
    lib.test(
      "end countdown stays visible for a last " .. kind .. " file in the " .. mode,
      function()
        local files = { ["a.txt"] = { "before" } }
        if kind ~= "added" then
          files["z.txt"] = { "before" }
        end
        local dir = h.repo(files)
        h.write(dir .. "/a.txt", { "after" })
        if kind == "deleted" then
          vim.fn.delete(dir .. "/z.txt")
        else
          h.write(dir .. "/z.txt", { "after" })
        end
        if mode == "commit page" then
          h.git(dir, "add", ".")
          h.git(dir, "commit", "-qm", "changes")
        end
        local screen = h.nvim(dir)
        screen:exec("vim.cmd('edit a.txt')")
        if mode == "Git pane" then
          screen:exec("vim.cmd('CodeDiff scm')")
        else
          screen:exec("vim.cmd('CodeDiff graph')")
          h.wait(screen, function()
            return screen:exec([[
            local g = require('codediff.ui.graph').get(vim.api.nvim_get_current_tabpage())
            return g and g.details and next(g.details.files or {}) ~= nil
          ]])
          end, "commit details did not load")
          screen:input("<CR><CR>")
          h.wait(screen, function()
            return screen:exec([[
            local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
            return s and s.stored_diff_result and #(s.stored_diff_result.changes or {}) > 0
              and not (s.refresh and (s.refresh.loading or s.refresh.running))
          ]])
          end, "first commit file did not load")
        end
        h.wait(screen, function()
          return screen:exec([[
          local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
          if not p or not p.tree then return false end
          for line = 1, vim.api.nvim_buf_line_count(p.bufnr) do
            local node = p.tree:get_node(line)
            if node and node.data and node.data.path == 'z.txt' then
              vim.api.nvim_win_set_cursor(p.winid, {line, 0})
              p.on_file_select(node.data)
              return true
            end
          end
          return false
        ]])
        end, "last changed file did not appear")
        h.wait(screen, function()
          return screen:exec([[
          local s = require('codediff.ui.lifecycle').get_session(vim.api.nvim_get_current_tabpage())
          if not s or not s.stored_diff_result then return false end
          local ref = s.single_side == 'original' and s.original or s.modified
          if not ref or not ref.absolute:find('z.txt', 1, true) then return false end
          if s.refresh and (s.refresh.loading or s.refresh.running) then return false end
          vim.api.nvim_set_current_win(s.modified_win or s.original_win)
          vim.api.nvim_win_set_cursor(0, {1, 0})
          return true
        ]])
        end, "last file did not finish loading")
        screen:await(function()
          return screen:text(screen.height, 1, screen.width):find("z.txt", 1, true)
        end, "filename and first hunk are missing before any navigation")
        for left = 5, 1, -1 do
          screen:input("<F7>")
          h.wait(screen, function()
            return screen:exec(string.format(
              [[
            local lifecycle = require('codediff.ui.lifecycle')
            local tab = vim.api.nvim_get_current_tabpage()
            local s, p = lifecycle.get_session(tab), lifecycle.get_panel_view(tab)
            if not s.end_armed or s.end_armed.left ~= %d or p.data.current_file_path ~= 'z.txt' then return false end
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              if vim.wo[win].winhighlight:find('CodeDiffHintEnd', 1, true) then
                local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), '\n')
                if text:find('press again %d time', 1, true) then return true end
              end
            end
            return false
          ]],
              left,
              left
            ))
          end, "end countdown missing or wrapped before confirmation")
        end
        screen:input("<F7>")
        h.wait(screen, function()
          return screen:exec([[
          local p = require('codediff.ui.lifecycle').get_panel_view(vim.api.nvim_get_current_tabpage())
          return p and p.data.current_file_path == 'a.txt'
        ]])
        end, "confirmed countdown did not wrap to the first file")
        h.wait(screen, function()
          return screen:exec([[
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local cfg = vim.api.nvim_win_get_config(win)
            if cfg.relative == 'editor' and cfg.row == 1 and cfg.height == 3 and type(cfg.border) == 'table' then
              local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), '\n')
              if text:find('You are back at the first change', 1, true) then return true end
            end
          end
          return false
        ]])
        end, "wrap confirmation did not appear at the top")
        screen:close()
      end
    )
  end
end
