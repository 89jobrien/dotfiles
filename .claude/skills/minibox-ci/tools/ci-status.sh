#!/usr/bin/env bash
# Check latest CI run status.
# Usage: ./ci-status.sh              (print status)
#        ./ci-status.sh watch        (live watch)
#        ./ci-status.sh logs         (show failed step logs)
#        ./ci-status.sh logs <ID>    (logs for specific run ID)
set -euo pipefail

command -v gh >/dev/null 2>&1 || { echo "error: gh CLI not found"; exit 1; }

WORKFLOW="${WORKFLOW:-ci.yml}"

get_latest_id() {
  gh run list --workflow="$WORKFLOW" --limit 1 --json databaseId --jq '.[0].databaseId'
}

print_status() {
  gh run list --workflow="$WORKFLOW" --limit 5
}

case "${1:-}" in
  watch)
    gh run watch "$(get_latest_id)"
    ;;
  logs)
    ID="${2:-$(get_latest_id)}"
    gh run view "$ID" --log-failed
    ;;
  *)
    print_status
    ;;
esac
