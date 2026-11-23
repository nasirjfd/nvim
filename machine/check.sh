#!/bin/zsh
# Is this machine in sync with the repo (and so with every other machine)? Report only: changes nothing.
# Each "FIX:" line says what to do; exit status 1 when anything needs fixing.
# Paths that differ per machine can be overridden:
#   NVIM_PLUGIN_SRC   multi-repo-code-diff source checkout (default ~/Can/Develop/nvim/multi-repo-code-diff)
#   SUPERNOVA_VENDOR  supernova-env-dev/vendor            (default ~/Can/Develop/php/supernova-env-dev/vendor)
# Whatever is set up on a machine outside this repo must be checked here (see AGENTS.md, "Machines stay in sync").

REPO=${0:A:h:h}
PLUGIN_SRC=${NVIM_PLUGIN_SRC:-$HOME/Can/Develop/nvim/multi-repo-code-diff}
VENDOR=${SUPERNOVA_VENDOR:-$HOME/Can/Develop/php/supernova-env-dev/vendor}
LAZY=${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy
GHOSTTY_MIN=1.4.0
TEST_DBS=32
fails=0

ok() { print -r -- "ok    $1"; }
fix() { print -r -- "FIX:  $1"; fails=$((fails + 1)); }
skip() { print -r -- "skip  $1"; }
same() { [[ -f $1 && -f $2 ]] && cmp -s "$1" "$2"; }

repo_state() { # name dir
  local name=$1 dir=$2
  if ! git -C "$dir" rev-parse 2>/dev/null; then fix "$name: no checkout at $dir (clone it or set the override)"; return; fi
  git -C "$dir" fetch -q 2>/dev/null || { fix "$name: git fetch failed"; return; }
  local behind ahead dirty
  behind=$(git -C "$dir" rev-list --count HEAD..@{u} 2>/dev/null)
  ahead=$(git -C "$dir" rev-list --count @{u}..HEAD 2>/dev/null)
  dirty=$(git -C "$dir" status --porcelain | wc -l | tr -d ' ')
  if [[ $behind != 0 ]]; then fix "$name: $behind commit(s) behind origin: git -C $dir pull --ff-only"; fi
  if [[ $ahead != 0 ]]; then fix "$name: $ahead local commit(s) not pushed: push them"; fi
  if [[ $dirty != 0 ]]; then fix "$name: $dirty uncommitted change(s): commit + push, or ask the user"; fi
  [[ $behind == 0 && $ahead == 0 && $dirty == 0 ]] && ok "$name: up to date with origin"
}

print "== repositories"
repo_state "nvim config" "$REPO"
repo_state "multi-repo-code-diff source" "$PLUGIN_SRC"
[[ $(git -C "$REPO" config core.hooksPath) == .githooks ]] && ok "git hooks (.githooks)" ||
  fix "git hooks: git -C $REPO config core.hooksPath .githooks"

print "== tools"
for cmd in nvim git jq fd rg tree-sitter fribidi herdr stylua luacheck; do
  command -v $cmd >/dev/null && ok "$cmd" || fix "$cmd missing: brew install ${cmd/#rg/ripgrep}"
done

print "== plugins (installed = lazy-lock.json)"
plugin_fails=0
# Disabled specs (enabled = false) stay in the lock but are never installed: ask lazy which ones are enabled.
enabled=" $(cd "$REPO" && NVIM_CONFIG_TESTS=1 nvim --headless -c \
  'lua io.stdout:write(table.concat(vim.tbl_keys(require("lazy.core.config").plugins), " "))' +qa 2>/dev/null) "
while read -r name commit; do
  dir=$LAZY/$name
  [[ $enabled != "  " && $enabled != *" $name "* ]] && continue
  if [[ ! -d $dir/.git && ! -f $dir/.git ]]; then fix "plugin $name not installed"; plugin_fails=1; continue; fi
  head=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
  if [[ $head != $commit ]]; then fix "plugin $name at ${head:0:7}, lock says ${commit:0:7}"; plugin_fails=1; fi
  if ! st=$(git -C "$dir" status --porcelain --untracked-files=no 2>&1) || [[ -n $st ]]; then
    fix "plugin $name has modified files (half-finished checkout?): git -C $dir reset --hard $commit"; plugin_fails=1
  fi
done < <(jq -r 'to_entries[] | "\(.key) \(.value.commit)"' "$REPO/lazy-lock.json")
if [[ $plugin_fails == 0 ]]; then ok "every plugin at its locked commit"
else print -r -- "      -> cd $REPO && NVIM_CONFIG_TESTS=1 nvim --headless '+Lazy! restore' +qa  (never without NVIM_CONFIG_TESTS=1: the daily sync races it)"; fi

if [[ $(uname) == Darwin ]]; then
  print "== Ghostty"
  G=/Applications/Ghostty.app/Contents/MacOS/ghostty
  if [[ -x $G ]]; then
    v=$($G +version 2>/dev/null | sed -n 's/^Ghostty //p' | head -1)
    if [[ $(printf '%s\n%s\n' "$GHOSTTY_MIN" "$v" | sort -V | head -1) == "$GHOSTTY_MIN" ]]; then ok "Ghostty $v (>= $GHOSTTY_MIN)"
    else fix "Ghostty $v is older than $GHOSTTY_MIN (the config needs it): update it (tip channel if stable is older)"; fi
    if $G +validate-config --config-file="$REPO/ghostty/config" >/dev/null 2>&1; then ok "ghostty/config validates"
    else fix "ghostty/config does not validate: $G +validate-config --config-file=$REPO/ghostty/config"; fi
  else
    fix "Ghostty not installed: brew install --cask ghostty"
  fi
  [[ ${HOME}/.config/ghostty/config.ghostty -ef $REPO/ghostty/config ]] && ok "~/.config/ghostty/config.ghostty -> repo" ||
    fix "~/.config/ghostty/config.ghostty must be a symlink: ln -sf $REPO/ghostty/config ~/.config/ghostty/config.ghostty"
  [[ -e $HOME/.config/ghostty/config ]] && fix "~/.config/ghostty/config exists next to config.ghostty (both load): remove it if it only repeats the repo's includes"
  keys=$(defaults read com.mitchellh.ghostty NSUserKeyEquivalents 2>/dev/null)
  [[ $keys == *'"Hide Others"'* && $keys == *'"Hide Ghostty"'* ]] && ok "Ghostty Hide Others / Hide Ghostty moved off cmd+alt+h / cmd+h" ||
    fix "Ghostty menu shortcuts not moved: run herdr/install.sh, then quit and reopen Ghostty"
fi

print "== herdr"
herdr_ok=1
for f in config.toml zen.sh send-ref.sh; do
  same "$REPO/herdr/$f" "$HOME/.config/herdr/$f" || { fix "~/.config/herdr/$f differs from herdr/$f"; herdr_ok=0; }
done
same "$REPO/herdr/ghostty-passthrough.conf" "$HOME/.config/ghostty/herdr-passthrough.conf" ||
  { fix "~/.config/ghostty/herdr-passthrough.conf differs from herdr/ghostty-passthrough.conf"; herdr_ok=0; }
if [[ $herdr_ok == 1 ]]; then ok "herdr files match the repo"
else print -r -- "      -> if the repo is newer: $REPO/herdr/install.sh ; if this machine's copy is the newer one: copy it into herdr/, commit, push"; fi

print "== gtab (retired, see AGENTS.md)"
gtab=()
command -v gtab >/dev/null && gtab+=("command $(command -v gtab)")
[[ -e $HOME/.config/gtab ]] && gtab+=("~/.config/gtab")
grep -lis gtab "$REPO/ghostty/config" "$HOME/.config/ghostty/config" \
  "$HOME/Library/Application Support/com.mitchellh.ghostty/config" 2>/dev/null | while read -r f; do gtab+=("include in $f"); done
(( ${#gtab} )) && fix "gtab still present (${(j:, :)gtab}): remove it, steps in AGENTS.md" || ok "no gtab"

print "== project files (local-projects/)"
if [[ -d $VENDOR ]]; then
  same "$REPO/local-projects/supernova-env-dev.nvim.lua" "$VENDOR/.nvim.lua" && ok "supernova .nvim.lua matches" ||
    fix "$VENDOR/.nvim.lua differs from local-projects/supernova-env-dev.nvim.lua (newer side wins; copy, re-trust, commit + push)"
  same "$REPO/local-projects/supernova-env-dev.ignore" "$VENDOR/.ignore" && ok "supernova .ignore matches" ||
    fix "$VENDOR/.ignore differs from local-projects/supernova-env-dev.ignore"
  if command -v docker >/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx supernova-env-dev-mysql-1; then
    n=$(docker exec supernova-env-dev-mysql-1 sh -c 'mysql -uroot -p"${MYSQL_ROOT_PASSWORD:-root}" -N -e "select count(distinct table_schema) from information_schema.tables where table_schema regexp \"^digiexpress(_log)?_[0-9]+$\""' 2>/dev/null)
    [[ $n == $((TEST_DBS * 2)) ]] && ok "test databases 1..$TEST_DBS" ||
      fix "test databases: $n of $((TEST_DBS * 2)); see local-projects/README.md (supernova-digiexpress-test-dbs.sh)"
  else
    skip "test databases (supernova mysql container not running)"
  fi
else
  skip "supernova not at $VENDOR (set SUPERNOVA_VENDOR if it lives elsewhere)"
fi

print
if [[ $fails == 0 ]]; then print "in sync"; else print "$fails thing(s) to fix"; exit 1; fi
