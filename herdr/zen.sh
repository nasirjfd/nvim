#!/bin/zsh
# Toggle zoom; hide pane borders/scrollbar only while zoomed.
C=~/.config/herdr/config.toml
out=$(herdr pane zoom --current --toggle)
if echo "$out" | grep -Eq '"zoomed": ?true'; then
  b=off; o=false; g=false; s=false
else
  b=auto; o=true; g=true; s=true
fi
sed -i '' -E \
 -e "s/^pane_borders = .*/pane_borders = \"$b\"/" \
 -e "s/^pane_outer_borders = .*/pane_outer_borders = $o/" \
 -e "s/^pane_gaps = .*/pane_gaps = $g/" \
 -e "s/^pane_scrollbars = .*/pane_scrollbars = $s/" $C
herdr server reload-config >/dev/null
