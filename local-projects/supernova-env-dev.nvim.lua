local root = vim.fn.expand("~/Can/Develop/php/supernova-env-dev/vendor")

-- Start the PHP workspace LSP before a PHP buffer is opened, so workspace
-- symbols are available from the project picker immediately after startup.
vim.g.project_lsp_filetypes = { "php" }

-- Never format this project on save (cmd+s, :w, autosave): formatting runs only when asked
-- (<leader>cf, shift+option+f, cmd+option+l).
vim.g.disable_format_on_save = true
local downgraded_codes = { 
  P1006 = vim.lsp.protocol.DiagnosticSeverity.Warning,
  P1013 = vim.lsp.protocol.DiagnosticSeverity.Warning 
}

vim.lsp.config("intelephense", {
  root_dir = root,
  -- Index only the packages the pickers show (.ignore / .gitignore) and what they depend on, not all of vendor:
  -- half the files, intelephense 1.5 GB -> 1.1 GB (core/intelephense-scope.lua).
  settings = {
    intelephense = { files = { exclude = require("core.intelephense-scope").excludes(root) } },
  },
  handlers = {
    ["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
      for _, d in ipairs(result and result.diagnostics or {}) do
        local severity = downgraded_codes[tostring(d.code)]
        if severity then
          d.severity = severity
        end
      end
      return vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx, config)
    end,
  },
})

require("codediff").setup({
  scm = {
    only_listed = true,
    repositories = vim.tbl_map(function(path)
      return root .. "/" .. path
    end, {
      "digikala/supernova-digiexpress",
      "digikala/supernova-hedwig",
      "digikala/supernova-flex",
      "digikala/supernova-digikala-shared",
      "digiexpress/digi-express-api",
      "digiexpress/digi-express-contract",
      "digiexpress/digi-express-util",
      "digiexpress/digi-express-infrastructure",
      "digiexpress/finance-contract",
      "digiexpress/drop-shipping-contract",
      "digiexpress/drop-shipping-api",
      "digiexpress/point-provider-contract",
      "digiexpress/ride-provider-contract",
      "http",
    }),
  },
})


-- Tests (Cmd+Shift+T): the same settings as .vscode/settings.json. PHPUnit runs inside the worker container
-- (phpunit.command, phpunit.paths) and the tests searched for are those of the project in --configuration
-- (phpunit.args): only digikala/supernova-digiexpress. To show more projects add
--   projects = { "digikala/supernova-flex", "digiexpress/digi-express-util", ... }
-- (each one is run with its own tests.xml).
require("modules.phpunit").configure({
  root = root,
  -- ${env} is where the variables of a parallel worker (parallel_env) go: inside the container
  command = 'docker compose exec -T -w /var/www/vendor worker /bin/sh -c "${env} ${php} ${phpargs} /var/www/vendor/bin/phpunit ${phpunitargs}"',
  paths = { [root] = "/var/www/vendor" },
  args = { "--configuration=digikala/supernova-digiexpress/tests.xml" },
  -- Tests that run at the same time must not share a database: Supernova's TEST_THREAD_ID picks the databases
  -- digiexpress_<N> and digiexpress_log_<N> (and the container cache, cache keys, redis db). Worker N of a
  -- parallel run gets TEST_THREAD_ID=N. The databases 1..15 exist (local-projects/supernova-digiexpress-test-dbs.sh
  -- clones digiexpress_1 into them); redis has 16 dbs, so 15 is the most.
  parallel_env = { TEST_THREAD_ID = "${slot}" },
  max_workers = 10, -- the worker container has 10 CPUs: 8-10 is as fast as 32 (6.3 s for everything)
})

-- Databases (<leader>D, or `db` in a shell = nvim +Dbee): the three mysql blocks of supernova-digiexpress's
-- config/local/mysql.yml (the active one and the commented ones). Host, user and password are read from that
-- file when Neovim starts, so they are never copied into the nvim config repo. The local block's host is the
-- docker service `mysql`: from this machine it is the published port MYSQL_PORT of supernova-env-dev/.env.
local function env_value(file, key)
  for line in io.lines(file) do
    local value = line:match("^%s*" .. key .. "%s*=%s*(%S+)")
    if value then
      return value
    end
  end
end
local env_file = vim.fn.fnamemodify(root, ":h") .. "/.env"
local mysql_port = vim.uv.fs_stat(env_file) and env_value(env_file, "MYSQL_PORT") or "3307"
require("modules.database").configure({
  name = "supernova",
  connections = require("modules.database.mysql_yml").connections(
    root .. "/digikala/supernova-digiexpress/config/local/mysql.yml",
    {
      mysql = { name = "mysql_local", host = "127.0.0.1", port = mysql_port },
      ["172.30.6.150"] = { name = "mysql_demo" },
      ["172.30.5.41"] = { name = "mysql_test" },
    }
  ),
})
