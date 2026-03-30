#!/usr/bin/env bash
# Generate SSH config entries for Tailscale devices
set -euo pipefail

# shellcheck source=scripts/lib/log.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/log.sh"
TAG="tailscale:ssh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/../backups"
OUTPUT_FILE="$SCRIPT_DIR/../ssh-config.generated"

find_latest_csv() {
    [[ -d "$BACKUP_DIR" ]] && find "$BACKUP_DIR" -name "devices-*.csv" -type f | sort -r | head -n 1
}

generate_ssh_config() {
    local csv_file
    csv_file=$(find_latest_csv)

    if [[ -z "$csv_file" ]]; then
        log_err "No device CSV files found in ${BACKUP_DIR}"
        log "Export devices from the Tailscale admin console and save to tailscale/backups/"
        exit 1
    fi

    log "Generating SSH config from: $(basename "$csv_file")"

    cat > "$OUTPUT_FILE" <<'EOF'
# Auto-generated Tailscale SSH config
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Source: $(basename "$csv_file")
#
# To use: Include this file in your ~/.ssh/config:
#   Include ~/.dotfiles/tailscale/ssh-config.generated

EOF

    tail -n +2 "$csv_file" | while IFS=',' read -r name id managed creator os os_version domain ts_version tags created last_seen expiry ips endpoints rest; do
        # Clean up fields
        name=$(echo "$name" | tr -d '"')
        os=$(echo "$os" | tr -d '"')
        ips=$(echo "$ips" | tr -d '"')
        domain=$(echo "$domain" | tr -d '"')

        # Extract IPv4
        ipv4=$(echo "$ips" | cut -d',' -f1)

        # Skip mobile devices
        if [[ "$os" == "android" ]] || [[ "$os" == "iOS" ]]; then
            continue
        fi

        # Generate host entry
        cat >> "$OUTPUT_FILE" <<EOF
Host ts-$name
    HostName $ipv4
    User joe
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    # Alternative: $domain
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR

EOF
    done

    log_ok "SSH config generated: $OUTPUT_FILE"
    log "Add to ~/.ssh/config:"
    echo "  Include $OUTPUT_FILE"
}

main() {
    generate_ssh_config
}

main "$@"
