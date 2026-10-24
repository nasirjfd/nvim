-- The Snacks explorer only reads `git status` of the top-level repo. Nested repos
-- (e.g. Composer packages cloned into vendor/ and un-ignored in the parent) show up
-- there as one untracked `??` directory, so every file looks red/untracked. Replace
-- that single entry with the nested repo's own status so only really changed files
-- are marked, with the usual M/A/?? indicators.
local function parse(dir, output)
  local ret = {}
  local entries = vim.split(output, "\0", { plain = true })
  local i = 1
  while i <= #entries do
    local status, file = entries[i]:match("^(..) (.+)$")
    if status then
      ret[#ret + 1] = { status = status, file = dir .. "/" .. file }
      if status:find("[RC]") then
        i = i + 1 -- renames/copies are followed by the original path
      end
    end
    i = i + 1
  end
  return ret
end

return {
  "folke/snacks.nvim",
  optional = true,
  init = function()
    vim.api.nvim_create_autocmd("VimEnter", {
      once = true,
      callback = function()
        local Git = require("snacks.explorer.git")
        local update, _update = Git.update, Git._update
        local on_update ---@type fun()?

        Git.update = function(cwd, opts)
          on_update = opts and opts.on_update
          return update(cwd, opts)
        end

        ---@param args string[]
        ---@param cb fun(output: string)
        local function git(args, cb)
          local cmd = { "git", "--no-pager", "--no-optional-locks" }
          vim.list_extend(cmd, args)
          vim.system(cmd, { text = true }, function(out)
            cb(out.code == 0 and out.stdout or "")
          end)
        end

        ---@param results snacks.explorer.git.Status[]
        ---@param done fun(results: snacks.explorer.git.Status[])
        local function expand(results, done)
          local root ---@type string?
          local jobs = {} ---@type {index: number, dir: string}[]
          for i, s in ipairs(results) do
            if s.status == "??" and s.file:sub(-1) == "/" then
              root = root or Snacks.git.get_root(s.file)
              if root and not vim.uv.fs_stat(s.file .. ".git") then
                jobs[#jobs + 1] = { index = i, dir = s.file }
              end
            end
          end
          if #jobs == 0 then
            return done(results)
          end

          -- git collapses an untracked folder into one entry; list what is inside to find repos
          local listed, pending = {}, #jobs
          for _, job in ipairs(jobs) do
            git({ "-C", root, "status", "--porcelain=v1", "-z", "-uall", "--", job.dir }, function(out)
              listed[job.index] = parse(root, out)
              pending = pending - 1
              if pending == 0 then
                local merged = {}
                for i, s in ipairs(results) do
                  if listed[i] and #listed[i] > 0 then
                    vim.list_extend(merged, listed[i])
                  else
                    merged[#merged + 1] = s
                  end
                end
                done(merged)
              end
            end)
          end
        end

        Git._update = function(cwd, results)
          expand(results, function(entries)
            local repos = {}
            for _, s in ipairs(entries) do
              if s.status == "??" and s.file:sub(-1) == "/" and vim.uv.fs_stat(s.file .. ".git") then
                repos[#repos + 1] = s.file:sub(1, -2)
              end
            end

            local nested, pending = {}, #repos
            local function finish()
              vim.schedule(function()
                local merged = {}
                for _, s in ipairs(entries) do
                  if not nested[s.file:sub(1, -2)] then
                    merged[#merged + 1] = s
                  end
                end
                for _, list in pairs(nested) do
                  vim.list_extend(merged, list)
                end
                if _update(cwd, merged) and on_update then
                  on_update()
                end
              end)
            end

            if pending == 0 then
              return finish()
            end
            for _, dir in ipairs(repos) do
              git({ "-C", dir, "status", "--porcelain=v1", "-z", "-unormal" }, function(out)
                nested[dir] = parse(dir, out)
                pending = pending - 1
                if pending == 0 then
                  finish()
                end
              end)
            end
          end)
          return false
        end
      end,
    })
  end,
}
