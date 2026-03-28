#!/usr/bin/env bash
# Check GHA self-hosted runner status on jobrien-vm.
# Usage: ./runner-status.sh [logs]   (logs = show recent journal output)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH="$SCRIPT_DIR/ssh-jobrien.sh"

case "${1:-}" in
  logs)
    "$SSH" "journalctl --user -u 'actions.runner.*' -n 80 --no-pager"
    ;;
  *)
    "$SSH" "
      echo '=== Runner units ==='
      systemctl --user list-units 'actions.runner.*' --no-legend 2>/dev/null || echo '(none)'
      echo ''
      echo '=== Runner service status ==='
      systemctl --user status 'actions.runner.*' --no-pager -l 2>/dev/null | head -20 || echo '(none)'
    "
    ;;
esac
