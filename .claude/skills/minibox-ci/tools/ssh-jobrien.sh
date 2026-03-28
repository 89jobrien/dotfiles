#!/usr/bin/env bash
# SSH into the VPS using 1Password credentials from ~/.claude/infra.toml
# Usage: ./ssh-jobrien.sh [COMMAND...]
#        (no args = interactive shell)
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/infra-load.sh
source "$SKILL_DIR/lib/infra-load.sh"

command -v op >/dev/null 2>&1      || { echo "error: op CLI not found"; exit 1; }
command -v sshpass >/dev/null 2>&1 || { echo "error: sshpass not found (brew install hudochenkov/sshpass/sshpass)"; exit 1; }

PW=$(op item get "$INFRA_VPS_OP_ITEM" --account="$INFRA_VPS_OP_ACCOUNT" --fields password --reveal)

exec sshpass -p "$PW" ssh \
  -o IdentitiesOnly=yes \
  -o IdentityAgent=none \
  -o PreferredAuthentications=password \
  "$INFRA_VPS_USER@$INFRA_VPS_IP" "$@"
