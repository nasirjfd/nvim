#!/usr/bin/env bash
# Fast automated checks of this configuration. Usage: tests/run.sh [--changed|--serial|--jobs N] [name filter]
cd "$(dirname "$0")/.." || exit 2
# Every clone refuses a failing push (.githooks/pre-push): switch it on the first time the tests run here.
if [ -d .git ] && [ "$(git config core.hooksPath)" != ".githooks" ]; then
  git config core.hooksPath .githooks && echo "tests/run.sh: enabled the pre-push test gate (git config core.hooksPath .githooks)"
fi
exec nvim --headless --noplugin -u NONE -i NONE -l tests/run.lua "$@"
