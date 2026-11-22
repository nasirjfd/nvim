-- ggc in the Git pane: a new branch with every change committed on it, in one go.
--
-- Two boxes: the branch name on top (typed), the commit message below it, written from the branch name while it is
-- typed: `feat/core-334-some text` -> `feat(core-334): some text`. The message can be changed too (Tab); once it is,
-- it no longer follows the branch. Enter: `git switch -c <branch>`, `git add -A`, `git commit -m <message>` in the
-- repository selected in the Git pane.
local M = {}

local api = vim.api
local ns = api.nvim_create_namespace("git_branch_commit")

--- The commit message for a branch name (pure), for every character typed so far:
---   feat -> feat, feat/ -> feat(), feat/core-33 -> feat(core-33), feat/core-334- -> feat(core-334): ,
---   feat/core-334-some-text -> feat(core-334): some text
function M.message_for(branch)
  branch = (branch or ""):gsub("^%s+", "")
  local kind, rest = branch:match("^([^/]*)/(.*)$")
  if not kind then
    return branch -- the type, being typed
  end
  -- the ticket ends at the separator after its number; what follows is the text
  local scope, text = rest:match("^(.-%d+)[-_ ](.*)$")
  if not scope then
    return kind .. "(" .. rest .. ")"
  end
  return kind .. "(" .. scope .. "): " .. text:gsub("[-_]", " "):gsub("  +", " ")
end

--- The branch name git gets: spaces become dashes.
function M.branch_name(typed)
  return (vim.trim(typed or ""):gsub("%s+", "-"))
end

local function git(root, args, on_done)
  vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }, function(out)
    vim.schedule(function()
      on_done(out.code == 0, vim.trim((out.stderr ~= "" and out.stderr) or out.stdout or ""))
    end)
  end)
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "New branch & commit" })
end

--- Create the branch, stage everything and commit (what Enter does).
function M.run(root, branch, message, on_done)
  on_done = on_done or function() end
  git(root, { "check-ref-format", "--branch", branch }, function(valid)
    if not valid then
      notify("Not a valid branch name: " .. branch, vim.log.levels.WARN)
      return on_done(false)
    end
    git(root, { "switch", "-c", branch }, function(ok, err)
      if not ok then
        notify("Could not create " .. branch .. ":\n" .. err, vim.log.levels.ERROR)
        return on_done(false)
      end
      git(root, { "add", "-A" }, function(added, add_err)
        if not added then
          notify("On " .. branch .. ", but staging failed:\n" .. add_err, vim.log.levels.ERROR)
          return on_done(false)
        end
        git(root, { "commit", "-m", message }, function(committed, commit_err)
          -- (the Git pane follows by itself: it watches the repository)
          if committed then
            notify("On " .. branch .. "\n" .. message)
          else
            notify(
              "On " .. branch .. ", but the commit failed:\n" .. commit_err,
              vim.log.levels.ERROR
            )
          end
          on_done(committed)
        end)
      end)
    end)
  end)
end

-- the repository of the Git pane's selection, else of the working directory
local function repository()
  local ok, root = pcall(function()
    local panel = require("codediff.ui.lifecycle").get_panel_view(api.nvim_get_current_tabpage())
    local actions = require("codediff.ui.explorer.actions")
    return panel and actions.root_of(panel, panel.tree and panel.tree:get_node())
  end)
  if ok and root then
    return root
  end
  local out = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
  return out.code == 0 and vim.trim(out.stdout) or nil
end

local state ---@type { branch_buf: integer, message_buf: integer, branch_win: integer, message_win: integer, keys_win: integer, root: string, edited: boolean }?

--- The two boxes (for tests).
function M.state()
  return state
end

function M.close()
  if not state then
    return
  end
  local s = state
  state = nil
  for _, win in ipairs({ s.branch_win, s.message_win, s.keys_win }) do
    if api.nvim_win_is_valid(win) then
      pcall(api.nvim_win_close, win, true)
    end
  end
  vim.cmd("stopinsert")
end

local function line(buf)
  return api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
end

local function confirm()
  if not state then
    return
  end
  local branch = M.branch_name(line(state.branch_buf))
  local message = vim.trim(line(state.message_buf))
  if branch == "" then
    notify("Write the branch name first", vim.log.levels.WARN)
    return
  end
  if message == "" or (not state.edited and not message:match("%): %S")) then
    notify("Write the text after the ticket: feat/core-334-some text", vim.log.levels.WARN)
    return
  end
  local root = state.root
  M.close()
  M.run(root, branch, message)
end

--- Open the two boxes (ggc).
function M.open()
  if state then
    api.nvim_set_current_win(state.branch_win)
    return
  end
  local root = repository()
  if not root then
    notify("Not in a git repository", vim.log.levels.WARN)
    return
  end
  local width = math.min(80, vim.o.columns - 6)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.max(1, math.floor((vim.o.lines - 7) / 2) - 2)
  local function box(r, title)
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "git_branch_commit"
    vim.b[buf].completion = false -- blink.cmp would take Tab and Enter
    local win = api.nvim_open_win(buf, false, {
      relative = "editor",
      row = r,
      col = col,
      width = width,
      height = 1,
      style = "minimal",
      border = "rounded",
      title = title,
      title_pos = "left",
      zindex = 60,
    })
    vim.wo[win].wrap = false
    vim.wo[win].winhighlight = "NormalFloat:Normal,FloatBorder:FloatBorder"
    return buf, win
  end
  local repo = vim.fs.basename(root)
  local branch_buf, branch_win =
    box(row, { { " New branch ", "Title" }, { "in " .. repo .. " ", "Comment" } })
  local message_buf, message_win = box(row + 3, { { " Commit message ", "Title" } })
  -- the keys: a line of its own under the boxes, away from the text being written
  local keys = {
    { "Enter", "create branch, stage all, commit" },
    { "Tab", "switch box" },
    { "Esc", "cancel" },
  }
  local text, marks = "", {}
  for i, k in ipairs(keys) do
    if i > 1 then
      text = text .. "   ·   "
    end
    marks[#marks + 1] = { #text, #text + #k[1], "Special" }
    text = text .. k[1] .. " "
    marks[#marks + 1] = { #text, #text + #k[2], "Comment" }
    text = text .. k[2]
  end
  local pad = math.max(0, math.floor((width + 2 - vim.fn.strdisplaywidth(text)) / 2))
  text = string.rep(" ", pad) .. text
  local keys_buf = api.nvim_create_buf(false, true)
  vim.bo[keys_buf].bufhidden = "wipe"
  api.nvim_buf_set_lines(keys_buf, 0, -1, false, { text })
  for _, m in ipairs(marks) do
    api.nvim_buf_set_extmark(keys_buf, ns, 0, m[1] + pad, { end_col = m[2] + pad, hl_group = m[3] })
  end
  local keys_win = api.nvim_open_win(keys_buf, false, {
    relative = "editor",
    row = row + 6,
    col = col,
    width = width + 2,
    height = 1,
    style = "minimal",
    border = "none",
    focusable = false,
    zindex = 60,
  })
  vim.wo[keys_win].winhighlight = "NormalFloat:Normal"
  state = {
    branch_buf = branch_buf,
    message_buf = message_buf,
    branch_win = branch_win,
    message_win = message_win,
    keys_win = keys_win,
    root = root,
    edited = false,
  }

  local updating = false
  -- every character typed in the branch box rewrites the message at once (before the screen is drawn)
  api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = branch_buf,
    callback = function()
      if state and not state.edited and api.nvim_buf_is_valid(message_buf) then
        updating = true
        api.nvim_buf_set_lines(message_buf, 0, -1, false, { M.message_for(line(branch_buf)) })
        updating = false
      end
    end,
  })
  api.nvim_buf_attach(message_buf, false, {
    on_lines = function()
      if not updating and state then
        -- typed by hand: it stops following the branch right away (cleared: it follows again)
        state.edited = true
      end
      vim.schedule(function()
        if not state or not api.nvim_buf_is_valid(message_buf) then
          return
        end
        if line(message_buf) == "" then
          state.edited = false
        end
      end)
    end,
  })

  for _, buf in ipairs({ branch_buf, message_buf }) do
    local other = buf == branch_buf and message_win or branch_win
    local function map(modes, lhs, fn)
      vim.keymap.set(modes, lhs, fn, { buffer = buf, nowait = true, silent = true })
    end
    map({ "i", "n" }, "<CR>", confirm)
    map({ "i", "n" }, "<Tab>", function()
      api.nvim_set_current_win(other)
      vim.cmd("startinsert!")
    end)
    map({ "i", "n" }, "<S-Tab>", function()
      api.nvim_set_current_win(other)
      vim.cmd("startinsert!")
    end)
    map("n", "<Esc>", M.close)
    map("n", "q", M.close)
    map({ "i", "n" }, "<C-c>", M.close)
    -- one box closed (a window command, :q): both go
    api.nvim_create_autocmd(
      "BufWipeout",
      { buffer = buf, once = true, callback = vim.schedule_wrap(M.close) }
    )
  end
  -- the screen behind dims, like behind every dialog
  require("core.modal-backdrop").dim_behind(branch_win)
  api.nvim_set_current_win(branch_win)
  vim.cmd("startinsert")
end

return M
