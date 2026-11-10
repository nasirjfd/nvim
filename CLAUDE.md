# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Personal Neovim (0.11+) configuration, not an application — there is no build step or test suite. See `AGENTS.md` for the shared agent guidance; the essentials are repeated here.

## Commands

- Validate config loads without errors: `nvim --headless -u ./init.lua '+qa'`
  - This may bootstrap lazy.nvim, install/update plugins, and touch the network (see Startup side effects).
- Format Lua: `stylua <files>` (config in `stylua.toml`: 2 spaces, 100 cols, prefer double quotes, always call parens).
- Lint Lua: `luacheck <files>` (config in `.luacheckrc`; `vim` is a declared global).
- Automated tests: `tests/run.sh [name filter]` (about 8 s). Each spec drives a real Neovim running this config in an embedded, rendered UI (`tests/screen.lua`) and asserts on the screen: grep toggles and hover, file names in pickers, find bar, Cmd+B sidebar toggling, `.http` startup, Cmd+Alt+Z, the HTTP and tests panes. Run it after every change to the config; add a spec in `tests/specs/` for every new feature or fixed bug. `NVIM_CONFIG_TESTS=1` (set by the runner) disables the lazy.nvim update checker and the daily auto-sync.
- The git plugin (`multi-repo-code-diff`) has its own suite: `./tests/run_tests.sh [spec|dir]` inside its folder (`integration/ui/conflict/scroll_sync_spec.lua`, `integration/ui/view/end_of_changes_spec.lua`, `e2e/conflict/scroll_sync_spec.lua` are the fast ones for the merge view and F7 behaviour; the `e2e/` specs that use the native watcher are slow). A few older specs fail on a clean checkout (`gutter_grid`, `move_keymap`, `keymap/golden_matrix`, `keymap/help`, `plugin/modules`, `plugin/setup`).
- Broader runtime diagnostics are interactive only: `:checkhealth`, `:checkhealth vim.lsp`, `:Lazy`, `:Mason`.

## Architecture

- `init.lua` → sets `exrc` and requires `core`. `lua/core/init.lua` loads, in order: `options`, `keymaps`, `gui-keymaps`, `autocmds`, `external-changes`, `sidebars`, then `lazy`.
- `lua/core/external-changes.lua` watches the cwd for files changed outside Neovim (e.g. by Claude Code): it reloads open buffers, sends `workspace/didChangeWatchedFiles` to servers that don't register watchers themselves (intelephense), and re-lints the current buffer.
- `lua/core/lazy.lua` bootstraps lazy.nvim and calls `require("lazy").setup({ import = "plugins" })`, so **every file in `lua/plugins/` is auto-imported as a spec** — adding a plugin means returning a spec table from a file there.
- `lua/core/gui-keymaps.lua` holds `<D-…>` (Cmd) bindings mirroring VS Code muscle memory; they are inert in terminals that don't forward Cmd.
- `snacks.nvim` is the central UI layer (picker, explorer, notifier, terminal). Many core and LSP keymaps call `Snacks.*` directly, and `gd`/`gD`/`gr`/`gi`/`gy` are defined in `lua/plugins/snacks.lua`, not in the LSP attach handler.

### HTTP Requests pane (`<leader>h`)

- `lua/modules/http_requests/` (self-contained, `require("modules.http_requests")` from `lua/core/init.lua`): a Snacks picker source with the sidebar layout. `parse.lua` (requests of an `.http`/`.rest` file, pure), `curl.lua` (clipboard curl -> request lines, the only place that touches Kulala's internal `kulala.parser.curl`), `edit.lua` (append a block through the buffer), `init.lua` (rows, actions, keys). The file list comes from the fd cache in `lua/core/http-files.lua`.
- Rows show only the request name (an unnamed one its URL); method names are muted coloured words, not badges. The picker title is empty because the title is the winbar (otherwise the search box repeats it).
- Keys in the pane: `l` opens / `h` closes a folder or file (`h` elsewhere goes to the parent; the terminal cursor is hidden in the list), Enter/click go to the request, Cmd+Shift+H (or `<leader>h`) opens it (Ghostty keybind `super+shift+h=csi:104;10u`), Ctrl+Enter or `r` run a request (through the file's own `<CR>` mapping from `ftplugin/http.lua`), `a` new request, `P` request from the clipboard curl (invalid -> a message), `R` refresh, `q`/Esc close. Ctrl+Enter needs the Ghostty keybind `ctrl+enter=csi:13;5u` (in `ghostty/config`; reload Ghostty).
- Two Snacks sidebars alive at the same moment make Neovim split the screen between them and hand the leftover rows to the command line (cmdheight 20). So the pane closes the Explorer *before* it opens (`make_room_for_http`), `Snacks.picker.pick` is wrapped to close the pane before an Explorer opens, and `close_now` destroys a picker's windows immediately. In a diff tab a request opens in another tab, never over the diff.
- It is one of three sidebars (Explorer, Git, HTTP) shown one at a time per tab: the wiring is in `lua/core/sidebars.lua` (`last_sidebar`, `source_of`) and `<D-b>` in `lua/core/gui-keymaps.lua`.
- Tests: `tests/specs/07_http_pane.lua`. The clipboard is read through `require("modules.http_requests").clipboard()` so tests can fake it.

### Tests pane (Cmd+Shift+T)

- neotest is the engine (finding tests, running them, results, signs in the files); the pane is ours: `lua/modules/phpunit/pane.lua` (a Snacks picker source "phpunit_tests", fed by a neotest consumer registered in `lua/plugins/neotest.lua`; rows: counts, Parallel checkbox with clickable − N + buttons, Run all, Run failed, then the Failed section, then parent folder -> test file -> every test; the Flat list toggle lists every test on its own, failed first), `runner.lua` (what runs: nearest, file, all, failed, last; parallel = one phpunit per test file, `workers` at a time), `options.lua` (parallel/workers, kept in `stdpath("state")/phpunit-options.json`), `plan.lua` (pure: command template, container paths, projects), `junit.lua` (the junit log -> results; neotest-phpunit's own reader crashes on a testcase without `file`), `init.lua` (the neotest adapter wrapping olimorris/neotest-phpunit). `lua/modules/pane_kit.lua` is what this pane and the HTTP pane share (hidden terminal cursor, title, mouse, opening files outside diff tabs, `refresh`: always refresh a pane through `kit.refresh`, a bare `picker:find()` puts the list on its first row for a frame and back, a visible flash).
- Keys: Cmd+Shift+T pane (Ghostty `super+shift+t=csi:116;10u`), `<leader>tt` test under the cursor, `tf` file, `ta` all, `tF` failed only, `tl` last, `tp` parallel on/off, `tx` stop, `to` output, `ts` pane. In the pane: Enter/click (fold, jump to a test, press a button), `r`/Ctrl+Enter run the row, `a`, `F`, `p`, `v` flat list, `+`/`-` workers (2–64, steps of 5 above 10), `x`, `o`, `l`/`h`, `e`/`E`.
- It is the fourth sidebar (Explorer, Git, HTTP, Tests): one at a time, wired in `lua/core/sidebars.lua` (`EXTRA`, `make_room`).
- A project turns it on in its `.nvim.lua` with `require("modules.phpunit").configure({ root, command, paths, args, projects, env })`, the same values as the VS Code PHPUnit extension (`phpunit.command` with `${php}`/`${phpargs}`/`${phpunitargs}`/`${workspaceFolder}`, `phpunit.paths`, `phpunit.args`). `--configuration=<project>/tests.xml` in `args` limits the search to that project (or list `projects`, each run with its own tests.xml). `supernova-env-dev/vendor/.nvim.lua` runs PHPUnit in the `worker` container. The junit log goes to `<root>/.neotest-results/` (a folder the container sees) and is deleted after the run. Without `configure` it runs `vendor/bin/phpunit` locally.
- neotest reads tests in a child Neovim with the runtimepath of setup time, so `neotest-phpunit` is required before `setup` in the plugin spec (else its `utils` module is not found there). neotest only starts looking for tests when something asks for them (`client:get_adapters()` in `attach`).
- Tests: `tests/specs/08_tests_pane.lua` (plan, junit, a run through a fake container, the pane in the layout), `09_tests_runner.lua` (all/file/nearest/failed/last/parallel/stop, the pane rows). A fake phpunit stands in for Docker.

### LSP (native 0.11 API, not nvim-lspconfig setup calls)

- Per-server configs live in top-level `lsp/<name>.lua` and are activated by the `vim.lsp.enable({...})` list in `lua/plugins/lsp.lua`. The filename must exactly match the enabled name (e.g. `laravel_lsp` → `lsp/laravel_lsp.lua`); a mismatch fails silently.
- Mason installs servers/tools via `mason-tool-installer` (`ensure_installed` in `lua/plugins/lsp.lua`), with `mason-lspconfig` `automatic_enable = false` — enabling is always explicit. `sourcekit-lsp` (Xcode) and `laravel-lsp` (Composer global) are not Mason-managed.
- Buffer-local LSP keymaps and diagnostics config are set in the `LspAttach` autocmd in `lua/plugins/lsp.lua`.
- Formatting is conform.nvim (`lua/plugins/formatting.lua`, format-on-save on); linting is nvim-lint (`lua/plugins/linting.lua`).

### Language tooling outside plugins

- `ftplugin/{go,rust,zig}.lua` define user commands (`:GoTest`, `:CargoRun`, `:ZigBuild`, …) documented in `doc/*.txt`. If you add/rename such a command, update the matching help file (and regenerate tags with `:helptags doc`).
- Custom filetype detection lives in `vim.filetype.add` in `lua/core/options.lua`.

## Startup side effects & gotchas

- `lua/core/lazy.lua` may run `cargo install tree-sitter-cli` if `tree-sitter` is missing, and runs a silent `lazy.sync()` at most once per day (stamp file in `stdpath("state")/lazy-auto-update`). The lazy checker also polls for updates every 4h.
- `lazy-lock.json` records plugin versions and changes as a result of syncs. Keep it consistent with intentional spec changes; inspect diffs to it rather than reverting them as noise.
- `exrc` is enabled: project-local `.nvim.lua` files execute on open. This repo's own `.nvim.lua` is a machine-specific override (template: `.nvim.lua.example`) — treat such files as executable config.
- `ghostty/config` is the Ghostty terminal config, tracked here but unrelated to Neovim loading.

## Herdr setup lives in this repo

The user's herdr (terminal workspace manager) setup is versioned in `herdr/` so it is identical on every machine: `config.toml`, `zen.sh`, `send-ref.sh`, `ghostty-passthrough.conf`, `install.sh`, `README.md`.

- This repo is the source of truth. On a new machine, pull and run `herdr/install.sh` (copies into `~/.config/herdr`, wires the Ghostty include, reloads herdr).
- Whenever you change anything in `~/.config/herdr/` or `~/.config/ghostty/herdr-passthrough.conf`, copy the changed files back into `herdr/`, then commit and push to `main` in the same turn. Update `install.sh`/`README.md` if the file set changes.
- Nvim-side pieces (`lua/core/herdr-ref.lua`, the `<D-l>` mapping in `lua/core/keymaps.lua`) live here too; `<leader>al` / `cmd+l` send `@file#Lx-y` to the herdr pane labelled `claude` via `send-ref.sh`.
- Commit messages: one short line, never any `Co-Authored-By` or Claude attribution.

## Project-local `.nvim.lua` files are synced here

Machine-local `.nvim.lua` files of projects (e.g. `supernova-env-dev/vendor/.nvim.lua`) are copied into `local-projects/` (see its README) so other machines get them.

- Whenever you change one of those `.nvim.lua` files, copy it into `local-projects/`, then commit and push to `main` in the same turn. Add new projects to the table in `local-projects/README.md`.
- Editing a `.nvim.lua` changes its exrc trust hash: re-trust it (`nvim --headless -u NONE -c "edit <file>" -c trust -c qa`) before running nvim there, or the trust prompt eats keystrokes sent by tmux tests (and they can end up typed into the open file).

