#!/usr/bin/env bash
# Fast automated checks of this configuration. Usage: tests/run.sh [name filter]
cd "$(dirname "$0")/.." || exit 2
exec nvim --headless --noplugin -u NONE -i NONE -l tests/run.lua "$@"
