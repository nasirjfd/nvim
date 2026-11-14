local M = {}
local api = vim.api

local function at_cursor(hunks, row)
  for _, hunk in ipairs(hunks or {}) do
    local first = math.max(1, hunk.added.start)
    local last = first + math.max(1, hunk.added.count) - 1
    if row >= first and row <= last then
      return hunk
    end
  end
end

function M.reset()
  local gs = require("gitsigns")
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local row = api.nvim_win_get_cursor(win)[1]
  local hunks = gs.get_hunks(buf)
  if not hunks then
    vim.notify(
      "Git hunks are not ready for this buffer",
      vim.log.levels.WARN,
      { title = "Revert Hunk" }
    )
    return
  end
  if at_cursor(hunks, row) then
    gs.reset_hunk()
    return
  end
  if vim.b[buf].reverting_staged_hunk then
    return
  end
  local tick = api.nvim_buf_get_changedtick(buf)
  vim.b[buf].reverting_staged_hunk = true
  -- The public get_hunks() only exposes unstaged hunks and can still be settling.
  -- Confirm the staged target using Gitsigns' own awaited hunk calculation: never
  -- call its stage/unstage toggle speculatively, which could stage a newer edit.
  require("gitsigns.async").run(function()
    local cache = require("gitsigns.cache").cache[buf]
    local unstaged = cache and cache:get_hunk(nil, true, false)
    local staged = not unstaged and cache and cache:get_hunk(nil, true, true)
    if
      not api.nvim_win_is_valid(win)
      or api.nvim_get_current_win() ~= win
      or api.nvim_get_current_buf() ~= buf
      or api.nvim_win_get_cursor(win)[1] ~= row
      or api.nvim_buf_get_changedtick(buf) ~= tick
    then
      if api.nvim_buf_is_valid(buf) then
        vim.b[buf].reverting_staged_hunk = nil
      end
      return
    end
    if unstaged then
      vim.b[buf].reverting_staged_hunk = nil
      gs.reset_hunk()
      return
    end
    if not staged then
      vim.b[buf].reverting_staged_hunk = nil
      vim.notify("No hunk at the cursor", vim.log.levels.INFO, { title = "Revert Hunk" })
      return
    end
    local keys = {
      ["y"] = { "revert_yes", mode = { "n", "i" } },
      ["Y"] = { "revert_yes", mode = { "n", "i" } },
      ["n"] = { "revert_no", mode = { "n", "i" } },
      ["N"] = { "revert_no", mode = { "n", "i" } },
      ["<Esc>"] = { "close", mode = { "n", "i" } },
    }
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Revert and unstage this hunk? [Y/n] (Enter = Yes)",
      snacks = {
        actions = {
          revert_yes = function(picker)
            picker.list:move(1, true)
            picker:action("confirm")
          end,
          revert_no = function(picker)
            picker.list:move(2, true)
            picker:action("confirm")
          end,
        },
        win = { input = { keys = keys }, list = { keys = keys } },
      },
    }, function(choice)
      if choice ~= "Yes" then
        if api.nvim_buf_is_valid(buf) then
          vim.b[buf].reverting_staged_hunk = nil
        end
        return
      end
      if
        not api.nvim_win_is_valid(win)
        or api.nvim_get_current_win() ~= win
        or api.nvim_get_current_buf() ~= buf
        or api.nvim_win_get_cursor(win)[1] ~= row
        or api.nvim_buf_get_changedtick(buf) ~= tick
      then
        if api.nvim_buf_is_valid(buf) then
          vim.b[buf].reverting_staged_hunk = nil
        end
        return
      end
      -- With no unstaged hunk at this position, stage_hunk toggles only the staged hunk
      -- back out of the index. Its callback runs after Gitsigns has refreshed the hunks.
      gs.stage_hunk(nil, nil, function(err)
        if api.nvim_buf_is_valid(buf) then
          vim.b[buf].reverting_staged_hunk = nil
        end
        if err then
          vim.notify(tostring(err), vim.log.levels.ERROR, { title = "Revert Hunk" })
          return
        end
        -- Never apply a delayed reset to a different buffer, cursor position, or newer edit.
        if
          not api.nvim_win_is_valid(win)
          or api.nvim_get_current_win() ~= win
          or api.nvim_get_current_buf() ~= buf
          or api.nvim_win_get_cursor(win)[1] ~= row
          or api.nvim_buf_get_changedtick(buf) ~= tick
        then
          return
        end
        -- Apply the already captured HEAD lines, not an optimistic post-unstage diff.
        -- Unstaged insertions above this hunk shift buffer offsets from index offsets.
        local first = staged.type == "delete" and staged.added.start or staged.added.start - 1
        cache:invalidate(true)
        api.nvim_buf_set_lines(buf, first, first + staged.added.count, false, staged.removed.lines)
        vim.notify("Reverted staged hunk", vim.log.levels.INFO, { title = "Revert Hunk" })
      end)
    end)
  end)
end

return M
