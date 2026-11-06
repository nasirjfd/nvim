# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Personal Neovim (0.11+) configuration, not an application — there is no build step or test suite. See `AGENTS.md` for the shared agent guidance; the essentials are repeated here.

## Commands

- Validate config loads without errors: `nvim --headless -u ./init.lua '+qa'`
  - This may bootstrap lazy.nvim, install/update plugins, and touch the network (see Startup side effects).
- Format Lua: `stylua <files>` (config in `stylua.toml`: 2 spaces, 100 cols, prefer double quotes, always call parens).
- Lint Lua: `luacheck <files>` (config in `.luacheckrc`; `vim` is a declared global).
- Broader runtime diagnostics are interactive only: `:checkhealth`, `:checkhealth vim.lsp`, `:Lazy`, `:Mason`.

## Architecture

- `init.lua` → sets `exrc` and requires `core`. `lua/core/init.lua` loads, in order: `options`, `keymaps`, `gui-keymaps`, `autocmds`, `external-changes`, `sidebars`, then `lazy`.
- `lua/core/external-changes.lua` watches the cwd for files changed outside Neovim (e.g. by Claude Code): it reloads open buffers, sends `workspace/didChangeWatchedFiles` to servers that don't register watchers themselves (intelephense), and re-lints the current buffer.
- `lua/core/lazy.lua` bootstraps lazy.nvim and calls `require("lazy").setup({ import = "plugins" })`, so **every file in `lua/plugins/` is auto-imported as a spec** — adding a plugin means returning a spec table from a file there.
- `lua/core/gui-keymaps.lua` holds `<D-…>` (Cmd) bindings mirroring VS Code muscle memory; they are inert in terminals that don't forward Cmd.
- `snacks.nvim` is the central UI layer (picker, explorer, notifier, terminal). Many core and LSP keymaps call `Snacks.*` directly, and `gd`/`gD`/`gr`/`gi`/`gy` are defined in `lua/plugins/snacks.lua`, not in the LSP attach handler.

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

