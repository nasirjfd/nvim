local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Bootstrap tree-sitter-cli if cargo is available
if vim.fn.executable("tree-sitter") == 0 and vim.fn.executable("cargo") == 1 then
  vim.notify("Installing tree-sitter-cli via cargo...", vim.log.levels.INFO)
  vim.fn.jobstart({ "cargo", "install", "--locked", "tree-sitter-cli" }, {
    on_exit = function(_, code)
      if code == 0 then
        vim.notify("tree-sitter-cli installed successfully!", vim.log.levels.INFO)
      else
        vim.notify("Failed to install tree-sitter-cli", vim.log.levels.WARN)
      end
    end,
  })
end

require("lazy").setup({ import = "plugins" }, {
  install = {
    missing = true,
    colorscheme = { "habamax" },
  },
  checker = {
    enabled = true,
    notify = true,
    frequency = 3600 * 4, -- check for updates every 4 hours
  },
  change_detection = {
    enabled = true,
    notify = false,
  },
  ui = {
    -- border = "rounded"
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tutor",
        "zipPlugin",
      },
    },
  },
})

-- ════════════════════════════════════════════════════════════════════════════
-- Keep plugins up to date automatically: sync once per day on startup,
-- silently (no UI popup), throttled via a stamp file so it doesn't hit the
-- network on every single launch.
-- ════════════════════════════════════════════════════════════════════════════
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.defer_fn(function()
      local stamp_file = vim.fn.stdpath("state") .. "/lazy-auto-update"
      local last = 0
      local f = io.open(stamp_file, "r")
      if f then
        last = tonumber(f:read("*a")) or 0
        f:close()
      end

      local now = os.time()
      if now - last < 24 * 60 * 60 then
        return
      end

      require("lazy").sync({ show = false })

      local wf = io.open(stamp_file, "w")
      if wf then
        wf:write(tostring(now))
        wf:close()
      end
    end, 1000)
  end,
})
