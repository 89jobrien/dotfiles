#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="ssh:sync"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519.pub}"
TAILSCALE_CSV_DIR="${ROOT_DIR}/tailscale/backups"
DRY_RUN="${DRY_RUN:-0}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Sync SSH public keys to all Tailscale devices.

Options:
  --key PATH         SSH public key to sync (default: ~/.ssh/id_ed25519.pub)
  --dry-run          Show what would be done without making changes
  --help             Show this help message

Environment:
  SSH_KEY            Path to SSH public key (default: ~/.ssh/id_ed25519.pub)
  DRY_RUN           Set to 1 for dry-run mode

Examples:
  $(basename "$0")                           # Sync default key to all devices
  $(basename "$0") --key ~/.ssh/work.pub     # Sync specific key
  $(basename "$0") --dry-run                 # Preview changes
EOF
}

find_latest_csv() {
  find "$TAILSCALE_CSV_DIR" -name "devices-*.csv" -type f 2>/dev/null | sort -r | head -n 1
}

sync_key_to_device() {
  local device_name="$1"
  local device_ip="$2"
  local ssh_alias="ts-$device_name"
  local pubkey_content

  if [[ ! -f "$SSH_KEY" ]]; then
    log_err "SSH key not found: $SSH_KEY"
    return 1
  fi

  pubkey_content="$(cat "$SSH_KEY")"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "would sync key to $ssh_alias ($device_ip)"
    return 0
  fi

  log "syncing key to $ssh_alias ($device_ip)..."

  # Use SSH to add the key (creates .ssh dir and authorized_keys if needed)
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$ssh_alias" \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
     grep -qF '$pubkey_content' ~/.ssh/authorized_keys 2>/dev/null || \
     (echo '$pubkey_content' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo 'added')"; then
    log_ok "$ssh_alias"
  else
    log_warn "$ssh_alias (connection failed or already present)"
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --key)
        SSH_KEY="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        log_err "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done

  local csv_file
  csv_file="$(find_latest_csv)"

  if [[ -z "$csv_file" ]]; then
    log_err "No Tailscale device CSV found in $TAILSCALE_CSV_DIR"
    log "Export devices from Tailscale admin console and save to tailscale/backups/"
    exit 1
  fi

  log "Using device list: $(basename "$csv_file")"
  log "SSH public key: $SSH_KEY"

  if [[ "$DRY_RUN" == "1" ]]; then
    log_warn "DRY RUN MODE - no changes will be made"
  fi

  section "Syncing SSH Keys to Tailscale Devices"

  local count=0
  tail -n +2 "$csv_file" | while IFS=',' read -r name id managed creator os os_version domain ts_version tags created last_seen expiry ips endpoints rest; do
    # Clean up fields
    name=$(echo "$name" | tr -d '"')
    os=$(echo "$os" | tr -d '"')
    ips=$(echo "$ips" | tr -d '"')

    # Extract IPv4
    ipv4=$(echo "$ips" | cut -d',' -f1)

    # Skip mobile devices
    if [[ "$os" == "android" ]] || [[ "$os" == "iOS" ]]; then
      continue
    fi

    sync_key_to_device "$name" "$ipv4"
    ((count++)) || true
  done

  log_ok "SSH key sync complete"
}

main "$@"
