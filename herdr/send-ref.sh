#!/bin/zsh
# Usage: send-ref.sh "<text>"  — types text into the pane labelled "claude" (same tab as caller, else anywhere).
[ -z "$1" ] && exit 1
panes=$(herdr pane list) || exit 1
tab=$(echo "$panes" | jq -r --arg p "$HERDR_PANE_ID" '.result.panes[] | select(.pane_id==$p) | .tab_id')
id=$(echo "$panes" | jq -r --arg t "$tab" '[.result.panes[] | select(.label=="claude")] | (map(select(.tab_id==$t)) + .)[0].pane_id // empty')
[ -z "$id" ] && { echo "no pane labelled claude" >&2; exit 2; }
herdr pane send-text "$id" "$1"
# focus the claude pane (switch tab first if it lives elsewhere)
ptab=$(echo "$panes" | jq -r --arg i "$id" '.result.panes[] | select(.pane_id==$i) | .tab_id')
[ "$ptab" != "$tab" ] && herdr tab focus "$ptab" >/dev/null 2>&1
printf '{"id":"send-ref","method":"pane.focus","params":{"pane_id":"%s"}}\n' "$id" | nc -U -w1 "$HERDR_SOCKET_PATH" >/dev/null 2>&1
