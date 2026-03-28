#!/usr/bin/env bash
# SSH into jobrien-vm using 1Password credentials.
# Usage: ./ssh-jobrien.sh [COMMAND...]
#        (no args = interactive shell)
set -euo pipefail

command -v op >/dev/null 2>&1     || { echo "error: op CLI not found"; exit 1; }
command -v sshpass >/dev/null 2>&1 || { echo "error: sshpass not found (brew install hudochenkov/sshpass/sshpass)"; exit 1; }

PW=$(op item get jobrien-vm --account=my.1password.com --fields password --reveal)

exec sshpass -p "$PW" ssh \
  -o IdentitiesOnly=yes \
  -o IdentityAgent=none \
  -o PreferredAuthentications=password \
  dev@100.105.75.7 "$@"
