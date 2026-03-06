#!/usr/bin/env bash
# Refresh Tailscale device inventory from the Tailscale admin console
set -euo pipefail

# shellcheck source=scripts/lib/log.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/log.sh"
TAG="tailscale:refresh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/../backups"

show_help() {
    cat <<EOF
Usage: $(basename "$0") <csv-file>

Imports a new Tailscale device export CSV and regenerates configs.

Steps to refresh:
  1. Go to https://login.tailscale.com/admin/machines
  2. Click "..." menu → "Export to CSV"
  3. Run: $(basename "$0") ~/Downloads/your-export.csv

This will:
  - Copy CSV to $BACKUP_DIR with timestamp
  - Regenerate SSH config
  - Check expiry dates
EOF
}

refresh_from_csv() {
    local source_csv="$1"

    if [[ ! -f "$source_csv" ]]; then
        log_err "File not found: $source_csv"
        exit 1
    fi

    # Validate it's a Tailscale export (check header)
    if ! head -n 1 "$source_csv" | grep -q "Device name"; then
        log_err "Invalid Tailscale export CSV (missing 'Device name' column)"
        exit 1
    fi

    # Generate timestamped filename
    local timestamp
    timestamp=$(date -u +"%Y-%m-%d")
    local dest_csv="$BACKUP_DIR/devices-$timestamp.csv"

    # Copy to backups
    cp "$source_csv" "$dest_csv"
    log_ok "Imported: $dest_csv"

    # Regenerate SSH config
    log "Regenerating SSH config..."
    "$SCRIPT_DIR/generate-ssh-config.sh"

    # Check expiry
    log "Checking expiry dates..."
    "$SCRIPT_DIR/check-expiry.sh"

    log_ok "Refresh complete!"
}

main() {
    if [[ $# -eq 0 ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        show_help
        exit 0
    fi

    refresh_from_csv "$1"
}

main "$@"
