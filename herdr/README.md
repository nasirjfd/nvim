# herdr setup (synced from ~/.config/herdr)

Files here are the source of truth. Run `./install.sh` on a new machine (needs `jq`, `nc`, herdr, Ghostty).

- `config.toml`: herdr config (keys, UI, theme)
- `zen.sh`: zoom toggle that hides pane borders while zoomed (`prefix+z`, `cmd+shift+enter`)
- `send-ref.sh`: sends `@file#Lx-y` to the pane labelled `claude` and focuses it (used by `<leader>al` / `cmd+l`, see `lua/core/herdr-ref.lua`)
- `ghostty-passthrough.conf`: unbinds Ghostty chords so herdr receives them
