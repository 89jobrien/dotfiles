#!/usr/bin/env bash
# Monitor Tailscale device key expiry dates
set -euo pipefail

# shellcheck source=scripts/lib/log.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/log.sh"
TAG="tailscale:expiry"

# shellcheck source=scripts/lib/cmd.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/cmd.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/../backups"

# Warn if keys expire within this many days
WARN_DAYS="${WARN_DAYS:-30}"

find_latest_csv() {
    [[ -d "$BACKUP_DIR" ]] && find "$BACKUP_DIR" -name "devices-*.csv" -type f | sort -r | head -n 1
}

check_expiry() {
    local csv_file
    csv_file=$(find_latest_csv)

    if [[ -z "$csv_file" ]]; then
        log_err "No device CSV files found in ${BACKUP_DIR}"
        log "Export devices from the Tailscale admin console and save to tailscale/backups/"
        exit 1
    fi

    log "Checking device expiry from: $(basename "$csv_file")"
    echo ""

    local now_ts
    if has_cmd gdate; then
        now_ts=$(gdate +%s)
    else
        now_ts=$(date +%s)
    fi

    local found_expiring=0

    tail -n +2 "$csv_file" | while IFS=',' read -r name id managed creator os os_version domain ts_version tags created last_seen expiry ips endpoints rest; do
        name=$(echo "$name" | tr -d '"')
        expiry=$(echo "$expiry" | tr -d '"')

        # Skip if no expiry
        if [[ -z "$expiry" ]]; then
            continue
        fi

        # Parse expiry date
        local expiry_ts
        if has_cmd gdate; then
            expiry_ts=$(gdate -d "$expiry" +%s)
        else
            expiry_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expiry" +%s 2>/dev/null || echo "0")
        fi

        if [[ "$expiry_ts" == "0" ]]; then
            continue
        fi

        # Calculate days until expiry
        local diff_seconds=$((expiry_ts - now_ts))
        local diff_days=$((diff_seconds / 86400))

        if [[ $diff_days -lt 0 ]]; then
            log_err "  $name: EXPIRED ${diff_days#-} days ago"
            found_expiring=1
        elif [[ $diff_days -lt $WARN_DAYS ]]; then
            log_warn "  $name: expires in $diff_days days ($expiry)"
            found_expiring=1
        fi
    done

    if [[ $found_expiring -eq 0 ]]; then
        log_ok "All devices have valid keys (>$WARN_DAYS days remaining)"
    fi
}

main() {
    local warn_days="${1:-$WARN_DAYS}"
    WARN_DAYS="$warn_days"
    check_expiry
}

main "$@"
