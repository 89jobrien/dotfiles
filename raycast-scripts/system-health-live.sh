#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title System Health Live
# @raycast.mode fullOutput
# @raycast.packageName Dev Bootstrap
# @raycast.icon 🖥️
# @raycast.needsConfirmation false

set -euo pipefail

if [[ -x "$HOME/dotfiles/scripts/system-health.sh" ]]; then
  exec "$HOME/dotfiles/scripts/system-health.sh" live
fi

echo "dotfiles health script not found at ~/dotfiles/scripts/system-health.sh"
exit 1
