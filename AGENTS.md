# Repository guidance

- This is a Neovim configuration, not an application with a standalone test suite. The entry point is `init.lua`; `lua/core/init.lua` loads core setup, and `lua/plugins/*.lua` are lazy.nvim plugin specs imported by `lua/core/lazy.lua`.
- Plugin versions are recorded in `lazy-lock.json`. Keep it in sync when intentionally changing plugin versions/specs; inspect lockfile changes rather than reverting them as incidental noise.
- Lua formatting is configured by `stylua.toml` (2 spaces, 100-column width, double quotes preferred). Format changed Lua with `stylua <files>` when available.
- For focused validation, run `nvim --headless -u ./init.lua '+qa'` to catch startup/config errors; this may bootstrap or update plugins and needs Neovim plus network access on a fresh setup. Interactive `:checkhealth` is the broader runtime diagnostic.
- `lua/core/lazy.lua` may install `tree-sitter-cli` via Cargo on startup if absent, and runs a throttled silent `lazy.sync()` once daily. Startup can therefore trigger installs/network activity.
- `init.lua` enables `exrc`; project-local `.nvim.lua` files may execute when opening a project. Treat them as executable configuration and inspect before enabling trust.
