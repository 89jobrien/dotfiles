#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Dev Up
# @raycast.mode fullOutput
# @raycast.packageName Dev Bootstrap
# @raycast.icon 🚀
# @raycast.needsConfirmation false

set -euo pipefail

if [[ ! -d "$HOME/dotfiles" ]]; then
  echo "dotfiles repo not found at ~/dotfiles"
  exit 1
fi

cd "$HOME/dotfiles"

if command -v mise >/dev/null 2>&1; then
  exec mise run up
elif command -v just >/dev/null 2>&1; then
  exec just up
else
  exec make up
fi
