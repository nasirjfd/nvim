# Repository guidance

- For this repository only, validate your changes, then commit and push them to `main` before reporting the work as complete. Commit only changes belonging to the task; do not include unrelated user work. Use a short, single-line commit message without agent attribution. If validation, commit, or push fails, report the blocker rather than claiming completion. Explicit user instructions not to commit or push take precedence.
- This is a Neovim configuration, not an application with a standalone test suite. The entry point is `init.lua`; `lua/core/init.lua` loads core setup, and `lua/plugins/*.lua` are lazy.nvim plugin specs imported by `lua/core/lazy.lua`.
- Plugin versions are recorded in `lazy-lock.json`. Keep it in sync when intentionally changing plugin versions/specs; inspect lockfile changes rather than reverting them as incidental noise.
- Lua formatting is configured by `stylua.toml` (2 spaces, 100-column width, double quotes preferred). Format changed Lua with `stylua <files>` when available.
- For focused validation, run `nvim --headless -u ./init.lua '+qa'` to catch startup/config errors; this may bootstrap or update plugins and needs Neovim plus network access on a fresh setup. Interactive `:checkhealth` is the broader runtime diagnostic.
- `lua/core/lazy.lua` may install `tree-sitter-cli` via Cargo on startup if absent, and runs a throttled silent `lazy.sync()` once daily. Startup can therefore trigger installs/network activity.
- `init.lua` enables `exrc`; project-local `.nvim.lua` files may execute when opening a project. Treat them as executable configuration and inspect before enabling trust.

## Related projects and real-project testing

- Requests to change the Git pane may require edits in the separate source repository `~/Can/Develop/nvim/multi-repo-code-diff` (`https://github.com/nasirjfd/multi-repo-code-diff`). Read that repository's own agent guidance before editing it. Do not confuse it with Lazy's installed copy at `~/.local/share/nvim/lazy/multi-repo-code-diff`; make source changes in the source checkout, not the installed copy.
- For changes to that fork: validate, commit and push the source changes; update the installed plugin through Lazy (`:Lazy update multi-repo-code-diff`); verify the installed commit and test in Neovim; then commit and push this config repository's updated `lazy-lock.json` and any related config changes before reporting completion. Do not include unrelated work or force-push. Report any blocker instead of claiming completion.
- In testing/performance discussions, "the project" means `~/Can/Develop/php/supernova-env-dev/vendor` (on the current machine, `/Users/nasirjd/Can/Develop/php/supernova-env-dev/vendor`), not the plugin source or a temporary fixture.
- Normally use focused automated tests. When the user explicitly asks to "test on the project" or reports slowness/a problem "on the project", also reproduce and validate in that real working directory. Inspect its `.nvim.lua` before executing/trusting it; do not modify project files or run destructive operations merely to test the editor.
- These paths describe this machine's layout. On another machine, locate the corresponding checkouts; if unavailable, ask for their locations rather than silently substituting temporary fixtures. Guidance is repository-scoped, not a global rule for unrelated projects.
