#!/bin/zsh
# Toggle zoom; hide pane borders/scrollbar only while zoomed.
# Config is applied BEFORE the zoom toggle so herdr sizes the pane with the right border settings
# (otherwise the zoomed pane stays 2 rows short and leaves dark lines at the bottom).
C=~/.config/herdr/config.toml
setcfg() {
  sed -i '' -E \
   -e "s/^pane_borders = .*/pane_borders = \"$1\"/" \
   -e "s/^pane_outer_borders = .*/pane_outer_borders = $2/" \
   -e "s/^pane_gaps = .*/pane_gaps = $2/" \
   -e "s/^pane_scrollbars = .*/pane_scrollbars = $2/" $C
  herdr server reload-config >/dev/null
}
cur=$(herdr pane layout --current | jq -r '.result.layout.zoomed')
if [ "$cur" = "true" ]; then want=false; setcfg auto true; else want=true; setcfg off false; fi
res=$(herdr pane zoom --current --toggle | jq -r '.result.zoom.zoomed')
# zoom did not take effect (e.g. single pane): put the config back
if [ "$res" != "$want" ]; then
  if [ "$want" = "true" ]; then setcfg auto true; else setcfg off false; fi
fi
