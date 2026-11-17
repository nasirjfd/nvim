# herdr setup (synced from ~/.config/herdr)

Files here are the source of truth. Run `./install.sh` on a new machine (needs `jq`, `nc`, herdr, Ghostty).

- `config.toml`: herdr config (keys, UI, theme)
- `zen.sh`: zoom toggle that hides pane borders while zoomed (`prefix+z`, `cmd+shift+enter`)
- `send-ref.sh`: sends `@file#Lx-y` to the pane labelled `claude` and focuses it (used by `<leader>al` / `cmd+l`, see `lua/core/herdr-ref.lua`)
- `ghostty-passthrough.conf`: unbinds Ghostty chords so herdr receives them
- It also forwards Cmd+I and Cmd+. as distinct CSI-u keys: completion in insert mode
  and LSP code actions in normal/visual/insert mode. Ctrl+Enter still runs items in HTTP/tests panes.
  Reload Ghostty after changing the include (Cmd+Shift+,). Other terminals need equivalent
  modified-key forwarding; plain Tab/Enter are deliberately not remapped. Existing Ctrl+Space
  (completion) and `<leader>ca` (code actions) remain available.

- Ghostty's **Hide Others** menu item is also cmd+alt+h (= `focus_pane_left`) and swallowed the first press, so `install.sh` moves it with `defaults write com.mitchellh.ghostty NSUserKeyEquivalents`. Needs a Ghostty restart to take effect.
