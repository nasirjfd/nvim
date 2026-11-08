-- <leader>gq: squash-merge a branch into the current branch, as one commit that keeps an author.
-- The three squash aliases that used to live in ~/.gitconfig, self-contained here so every machine
-- has them:
--   last  author/date of the branch's last commit; fetches the branch first, deletes it locally
--         and on every remote afterwards (squash-author-last)
--   first author/date of the branch's first commit (squash-author-first)
--   by    author/date of a commit you pick (squash-author-by)
-- The commit message lists every squashed commit ("*subject" + body), oldest first.
local M = {}

local MODES = {
  { id = "last", label = "Author of the last commit", detail = "fetch, squash, then delete the branch locally and on the remotes" },
  { id = "first", label = "Author of the first commit", detail = "squash, keep the branch" },
  { id = "by", label = "Author of a commit I pick", detail = "squash, keep the branch" },
}

-- Run git in `root` inside a coroutine; returns ok, stdout, stderr.
local function git(root, args)
  local co = coroutine.running()
  vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }, function(result)
    vim.schedule(function()
      coroutine.resume(co, result.code == 0, vim.trim(result.stdout or ""), vim.trim(result.stderr or ""))
    end)
  end)
  return coroutine.yield()
end

local function await(fn, ...)
  local co = coroutine.running()
  local args = { ... }
  args[#args + 1] = function(...)
    local results = { ... }
    vim.schedule(function()
      coroutine.resume(co, unpack(results))
    end)
  end
  fn(unpack(args))
  return coroutine.yield()
end

local function select(items, opts)
  return await(vim.ui.select, items, opts)
end

local function confirm(title, lines, yes)
  local ok, box = pcall(require, "codediff.ui.graph.confirm")
  if ok then
    local co = coroutine.running()
    local answered = false
    local win = box.ask({ title = title, lines = lines, yes = yes, no = "Cancel" }, function()
      answered = true
    end)
    -- yes or no, the box closes: resume then with the answer
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win),
      once = true,
      callback = function()
        vim.schedule(function()
          coroutine.resume(co, answered)
        end)
      end,
    })
    return coroutine.yield()
  end
  return vim.fn.confirm(title .. "\n\n" .. table.concat(lines, "\n"), "&" .. yes .. "\n&Cancel", 2) == 1
end

local function fail(msg)
  vim.notify(msg, vim.log.levels.ERROR, { title = "Squash" })
end

-- The repository of the current file, else of the working directory.
local function repo_root()
  local dir = vim.fn.expand("%:p:h")
  if dir == "" or vim.fn.isdirectory(dir) == 0 then
    dir = vim.fn.getcwd()
  end
  local result = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, { text = true }):wait()
  return result.code == 0 and vim.trim(result.stdout) or nil
end

-- "*subject\nbody\n" per commit, oldest first, runs of blank lines squeezed (like the alias's sed).
local function message(root, ref)
  local _, out = git(root, { "log", ref, "--not", "HEAD", "--reverse", "--format=*%s%n%b%n" })
  local lines, blank = {}, false
  for _, line in ipairs(vim.split(out, "\n", { plain = true })) do
    local is_blank = line:match("^%s*$") ~= nil
    if not (is_blank and blank) then
      lines[#lines + 1] = line
    end
    blank = is_blank
  end
  return vim.trim(table.concat(lines, "\n"))
end

local function author_of(root, commit)
  local _, out = git(root, { "log", "-1", "--format=%an <%ae>%n%ad", commit })
  local author, date = out:match("^(.-)\n(.*)$")
  return author, date
end

local function run(mode, root)
  local name = vim.fn.fnamemodify(root, ":t")
  local _, dirty = git(root, { "status", "--porcelain", "--untracked-files=no" })
  if dirty ~= "" then
    return fail(name .. ": commit or stash your changes first")
  end
  local _, current = git(root, { "branch", "--show-current" })
  local _, remotes_out = git(root, { "remote" })
  local remotes = remotes_out == "" and {} or vim.split(remotes_out, "\n")

  -- the branch
  local _, refs = git(root, { "for-each-ref", "--sort=-committerdate", "--format=%(refname:short)", "refs/heads", "refs/remotes" })
  local branches = vim.tbl_filter(function(ref)
    return ref ~= current and not ref:match("/HEAD$") and ref:match("%S") ~= nil
  end, vim.split(refs, "\n"))
  local picked = select(branches, { prompt = "Squash which branch into " .. (current ~= "" and current or "HEAD") .. "?" })
  if not picked then
    return
  end

  local ref, branch, commit
  if mode == "last" then
    branch = picked
    for _, remote in ipairs(remotes) do
      branch = branch:gsub("^" .. vim.pesc(remote) .. "/", "")
    end
    vim.notify("Fetching " .. branch .. "…", vim.log.levels.INFO, { title = "Squash" })
    for _, remote in ipairs(remotes) do
      git(root, { "fetch", remote, branch }) -- a remote without the branch is fine
    end
    local remote_ref
    for _, remote in ipairs({ "origin", unpack(remotes) }) do
      local ok = git(root, { "rev-parse", "--verify", "--quiet", "refs/remotes/" .. remote .. "/" .. branch })
      if ok then
        remote_ref = "refs/remotes/" .. remote .. "/" .. branch
        break
      end
    end
    ref = remote_ref or ("refs/heads/" .. branch)
    if not git(root, { "rev-parse", "--verify", "--quiet", ref }) then
      return fail(branch .. " does not exist on any remote")
    end
    commit = ref
  else
    local _, full = git(root, { "rev-parse", "--symbolic-full-name", picked })
    ref = full ~= "" and full or picked
    local _, list = git(root, { "log", ref, "--not", "HEAD", "--reverse", "--format=%h%x09%an%x09%ad%x09%s", "--date=short" })
    if list == "" then
      return fail(picked .. " has nothing that isn't already in " .. current)
    end
    local commits = vim.split(list, "\n")
    if mode == "first" then
      commit = commits[1]:match("^(%S+)")
    else
      local choice = select(commits, {
        prompt = "Whose author and date?",
        format_item = function(item)
          local hash, author, date, subject = item:match("^(.-)\t(.-)\t(.-)\t(.*)$")
          return ("%s  %s  %s  %s"):format(hash, date, author, subject)
        end,
      })
      if not choice then
        return
      end
      commit = choice:match("^(%S+)")
    end
  end

  local author, date = author_of(root, commit)
  local msg = message(root, ref)
  if msg == "" then
    return fail(picked .. " has nothing that isn't already in " .. current)
  end
  local count = 0
  for _ in ("\n" .. msg):gmatch("\n%*") do
    count = count + 1
  end

  local lines = {
    ("Squash %s into %s (%s), %d commit%s"):format(picked, current, name, count, count == 1 and "" or "s"),
    "Author: " .. author,
    "Date:   " .. date,
  }
  if mode == "last" then
    lines[#lines + 1] = "Then delete " .. branch .. " locally and on: " .. table.concat(remotes, ", ")
  end
  if not confirm("Squash", lines, "Squash") then
    return
  end

  local ok, _, err = git(root, { "merge", "--squash", ref })
  if not ok then
    return fail("merge --squash stopped:\n" .. err)
  end
  ok, _, err = git(root, { "commit", "-m", msg, "--author=" .. author, "--date=" .. date })
  if not ok then
    return fail("commit failed:\n" .. err)
  end

  local report = { ("Squashed %s into %s as one commit by %s"):format(picked, current, author) }
  if mode == "last" then
    if git(root, { "branch", "-D", branch }) then
      report[#report + 1] = "deleted local " .. branch
    end
    for _, remote in ipairs(remotes) do
      if git(root, { "push", remote, "--delete", branch }) then
        report[#report + 1] = "deleted " .. remote .. "/" .. branch
      else
        report[#report + 1] = remote .. "/" .. branch .. " not found"
      end
      git(root, { "fetch", remote, "--prune" })
    end
  end
  vim.notify(table.concat(report, "\n"), vim.log.levels.INFO, { title = "Squash" })
end

function M.open()
  local root = repo_root()
  if not root then
    return fail("Not inside a git repository")
  end
  coroutine.wrap(function()
    local mode = select(MODES, {
      prompt = "Squash merge (" .. vim.fn.fnamemodify(root, ":t") .. ")",
      format_item = function(item)
        return item.label .. "  ·  " .. item.detail
      end,
    })
    if mode then
      run(mode.id, root)
    end
  end)()
end

vim.keymap.set("n", "<leader>gq", M.open, { desc = "Squash merge a branch (pick author mode)" })

return M
