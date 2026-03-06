#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="colima:autostart"

PLIST_TARGET="$HOME/Library/LaunchAgents/com.colima.autostart.plist"

disable_autostart() {
  if [[ ! -f "$PLIST_TARGET" ]]; then
    log_skip "Colima auto-start not installed"
    return 0
  fi

  log "Disabling Colima auto-start..."

  # Unload the agent
  if launchctl list | grep -q com.colima.autostart; then
    launchctl unload "$PLIST_TARGET"
  fi

  # Remove plist
  rm "$PLIST_TARGET"

  log_ok "Colima auto-start disabled"
  log "Colima will no longer start automatically on login"
  log "Docker commands will still auto-start Colima on demand"
}

main() {
  disable_autostart
}

main "$@"
