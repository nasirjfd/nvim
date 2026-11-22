#!/bin/zsh
# Install the herdr setup on this machine: copies the files here into ~/.config/herdr,
# wires the Ghostty passthrough include, and reloads herdr. Re-run after pulling changes.
set -e
D=${0:A:h}
mkdir -p ~/.config/herdr ~/.config/ghostty
cp "$D/config.toml" ~/.config/herdr/config.toml
cp "$D/zen.sh" "$D/send-ref.sh" ~/.config/herdr/ && chmod +x ~/.config/herdr/{zen.sh,send-ref.sh}
cp "$D/ghostty-passthrough.conf" ~/.config/ghostty/herdr-passthrough.conf
G=~/.config/ghostty/config
INC='config-file = "'$HOME'/.config/ghostty/herdr-passthrough.conf"'
grep -qF 'herdr-passthrough.conf' "$G" 2>/dev/null || echo "$INC" >> "$G"
# Ghostty's menu has "Hide Others" on cmd+alt+h, the same chord as focus_pane_left: macOS menus win over
# the terminal, so a press hid other apps instead of reaching herdr (it "needed a second press"). Move
# the menu item away. "Hide Ghostty" (cmd+h) moves too: cmd+h is find and replace in Neovim.
# Always -dict-add: a `defaults write ... -dict` replaces the whole list and loses the other entries
# (that is how "Hide Others" came back once).
defaults write com.mitchellh.ghostty NSUserKeyEquivalents -dict-add "Hide Others" '@~^$h'
defaults write com.mitchellh.ghostty NSUserKeyEquivalents -dict-add "Hide Ghostty" '@~^$v'
for item in "Hide Others" "Hide Ghostty"; do
  if ! defaults read com.mitchellh.ghostty NSUserKeyEquivalents | grep -q "\"$item\""; then
    echo "Ghostty menu shortcut for \"$item\" was not moved" >&2
    exit 1
  fi
done
herdr server reload-config 2>/dev/null || true
echo "herdr config installed (reload Ghostty with cmd+shift+, ; quit and reopen Ghostty once for the menu change)"
