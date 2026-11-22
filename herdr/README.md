# herdr setup (synced from ~/.config/herdr)

Files here are the source of truth. Run `./install.sh` on a new machine (needs `jq`, `nc`, herdr, Ghostty).

- `config.toml`: herdr config (keys, UI, theme)
- `zen.sh`: zoom toggle that hides pane borders while zoomed (`prefix+z`, `cmd+shift+enter`)
- `send-ref.sh`: sends `@file#Lx-y` to the pane labelled `claude` and focuses it (used by `<leader>al` / `cmd+l`, see `lua/core/herdr-ref.lua`)
- `ghostty-passthrough.conf`: unbinds Ghostty chords so herdr receives them; cmd+alt+hjkl (pane focus) are sent as exact CSI-u bytes instead, because through Ghostty's key encoder a quick cmd+alt+h then cmd+alt+l typed a plain `l` into the pane
- It also forwards Cmd+I and Cmd+. as distinct CSI-u keys: completion in insert mode
  and LSP code actions in normal/visual/insert mode. Ctrl+Enter still runs items in HTTP/tests panes.
  Reload Ghostty after changing the include (Cmd+Shift+,). Other terminals need equivalent
  modified-key forwarding; plain Tab/Enter are deliberately not remapped. Existing Ctrl+Space
  (completion) and `<leader>ca` (code actions) remain available.

- Ghostty's **Hide Others** menu item is also cmd+alt+h (= `focus_pane_left`) and swallowed the first press, so `install.sh` moves it (and **Hide Ghostty**, cmd+h, which is find and replace in Neovim) with `defaults write com.mitchellh.ghostty NSUserKeyEquivalents -dict-add`. Needs a Ghostty restart (quit and reopen) to take effect. Never write that key with `-dict`: it replaces the whole list, and Hide Others is back on cmd+alt+h. Check with `defaults read com.mitchellh.ghostty NSUserKeyEquivalents` (both entries listed). A Ghostty started before that change keeps the old shortcut: cmd+alt+h needs two presses after coming back from another app (the first hides the other apps). `install.sh` asks the running Ghostty and says when it must be quit and reopened.
