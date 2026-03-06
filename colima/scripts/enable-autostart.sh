#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="colima:autostart"

PLIST_SOURCE="$SCRIPT_DIR/../com.colima.autostart.plist"
PLIST_TARGET="$HOME/Library/LaunchAgents/com.colima.autostart.plist"

enable_autostart() {
  if [[ ! -f "$PLIST_SOURCE" ]]; then
    log_err "LaunchAgent plist not found: $PLIST_SOURCE"
    exit 1
  fi

  log "Installing Colima auto-start LaunchAgent..."

  # Create LaunchAgents directory if it doesn't exist
  mkdir -p "$HOME/Library/LaunchAgents"

  # Copy plist
  cp "$PLIST_SOURCE" "$PLIST_TARGET"

  # Load the agent
  if launchctl list | grep -q com.colima.autostart; then
    log_skip "LaunchAgent already loaded, reloading..."
    launchctl unload "$PLIST_TARGET" 2>/dev/null || true
  fi

  launchctl load "$PLIST_TARGET"

  log_ok "Colima auto-start enabled"
  log "Colima will start automatically on next login"
  log "To start now: colima-start"
}

main() {
  enable_autostart
}

main "$@"
