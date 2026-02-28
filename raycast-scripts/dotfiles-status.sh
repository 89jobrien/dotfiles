#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Dotfiles Status
# @raycast.mode fullOutput
# @raycast.packageName Dev Bootstrap
# @raycast.icon 🧩
# @raycast.needsConfirmation false

set -euo pipefail

if [[ ! -d "$HOME/dotfiles/.git" ]]; then
  echo "dotfiles repo not found at ~/dotfiles"
  exit 1
fi

cd "$HOME/dotfiles"
git status -sb
echo
git log --oneline -n 8
