local root = vim.fn.expand("~/Can/Develop/php/supernova-env-dev/vendor")

-- Never format this project on save (cmd+s, :w, autosave): formatting runs only when asked
-- (<leader>cf, shift+option+f, cmd+option+l).
vim.g.disable_format_on_save = true
local downgraded_codes = { 
  P1006 = vim.lsp.protocol.DiagnosticSeverity.Warning,
  P1013 = vim.lsp.protocol.DiagnosticSeverity.Warning 
}

vim.lsp.config("intelephense", {
  root_dir = root,
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

-- Use the project's phpstan: Mason's newer one crashes on the project's old nikic/php-parser (v4).
local lint = require("lint")
lint.linters.phpstan.cmd = root .. "/bin/phpstan"
lint.linters.phpstan.args = {
  "analyse",
  "--error-format=json",
  "--no-progress",
  -- The default 128M crashes the worker on big files; nvim-lint then shows that as an error on line 1.
  "--memory-limit=2G",
  "--autoload-file=" .. root .. "/autoload.php",
}
-- This phpstan prints a few stray "x" characters before its JSON even with --no-progress, which
-- makes nvim-lint's parser fail (shown as an error on line 1). Drop everything before the JSON.
local parse_phpstan = lint.linters.phpstan.parser
lint.linters.phpstan.parser = function(output, bufnr)
  local json_start = output and output:find("{", 1, true)
  if not json_start then
    return {}
  end
  return parse_phpstan(output:sub(json_start), bufnr)
end

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
