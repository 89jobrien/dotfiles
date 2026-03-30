#!/usr/bin/env bash
# Parse Tailscale device export and extract useful information
set -euo pipefail

# shellcheck source=scripts/lib/log.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/log.sh"
TAG="tailscale:parse"

# shellcheck source=scripts/lib/cmd.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/cmd.sh"

LATEST_CSV=""

find_latest_csv() {
    local backup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/backups"
    if [[ ! -d "$backup_dir" ]]; then
        log_err "backups directory not found: $backup_dir"
        log "Export devices from the Tailscale admin console and save to tailscale/backups/"
        exit 1
    fi
    LATEST_CSV=$(find "$backup_dir" -name "devices-*.csv" -type f | sort -r | head -n 1)

    if [[ -z "$LATEST_CSV" ]]; then
        log_err "No device CSV files found in $backup_dir"
        log "Export devices from the Tailscale admin console and save to tailscale/backups/"
        exit 1
    fi

    log "Using: $LATEST_CSV"
}

list_devices() {
    log "Tailscale Devices:"
    echo ""
    tail -n +2 "$LATEST_CSV" | while IFS=',' read -r name id managed creator os os_version domain ts_version tags created last_seen expiry ips endpoints rest; do
        # Remove quotes
        name=$(echo "$name" | tr -d '"')
        os=$(echo "$os" | tr -d '"')
        ips=$(echo "$ips" | tr -d '"')
        expiry=$(echo "$expiry" | tr -d '"')

        # Extract IPv4 (first IP before comma in the IPs field)
        ipv4=$(echo "$ips" | cut -d',' -f1)

        printf "  %-25s %-12s %-20s %s\n" "$name" "$os" "$ipv4" "$expiry"
    done
}

list_device_names() {
    tail -n +2 "$LATEST_CSV" | cut -d',' -f1 | tr -d '"'
}

get_device_ip() {
    local device_name="$1"
    tail -n +2 "$LATEST_CSV" | while IFS=',' read -r name id managed creator os os_version domain ts_version tags created last_seen expiry ips endpoints rest; do
        name=$(echo "$name" | tr -d '"')
        if [[ "$name" == "$device_name" ]]; then
            ips=$(echo "$ips" | tr -d '"')
            echo "$ips" | cut -d',' -f1
            break
        fi
    done
}

get_device_domain() {
    local device_name="$1"
    tail -n +2 "$LATEST_CSV" | while IFS=',' read -r name id managed creator os os_version domain ts_version tags created last_seen expiry ips endpoints rest; do
        name=$(echo "$name" | tr -d '"')
        if [[ "$name" == "$device_name" ]]; then
            echo "$domain" | tr -d '"'
            break
        fi
    done
}

show_help() {
    cat <<EOF
Usage: $(basename "$0") [COMMAND]

Commands:
  list              List all devices with IPs and expiry
  names             List device names only
  ip <device>       Get IP for a specific device
  domain <device>   Get domain for a specific device
  help              Show this help

Examples:
  $(basename "$0") list
  $(basename "$0") ip jobrien
  $(basename "$0") domain josephs-macbook-air
EOF
}

main() {
    find_latest_csv

    case "${1:-list}" in
        list)
            list_devices
            ;;
        names)
            list_device_names
            ;;
        ip)
            if [[ -z "${2:-}" ]]; then
                log_err "Usage: $0 ip <device-name>"
                exit 1
            fi
            get_device_ip "$2"
            ;;
        domain)
            if [[ -z "${2:-}" ]]; then
                log_err "Usage: $0 domain <device-name>"
                exit 1
            fi
            get_device_domain "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_err "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
