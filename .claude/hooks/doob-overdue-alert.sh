#!/usr/bin/env bash
# doob-overdue-alert.sh — SessionStart hook
# On session start in the doob project, checks for overdue todos and stale in-progress items.
# Writes alert to log (SessionStart stdout is not shown in UI).

set -euo pipefail

CWD=$(pwd)
LOG="/tmp/doob-session-alert.log"

# Only run in the doob project
[[ "$CWD" == *"/dev/doob"* ]] || exit 0

command -v doob &>/dev/null || exit 0
command -v jq &>/dev/null || exit 0

TODAY=$(date +%Y-%m-%d)

# Fetch all pending todos with due dates
TODOS=$(doob todo list --status pending --json 2>/dev/null) || exit 0

OVERDUE=$(echo "$TODOS" | jq -r --arg today "$TODAY" \
  '.todos[] | select(.due_date != null and .due_date < $today) | "  [\(.uuid[:8])] \(.content) (due: \(.due_date))"' 2>/dev/null)

# Fetch stale in-progress (updated > 7 days ago)
IN_PROGRESS=$(doob todo list --status in_progress --json 2>/dev/null) || true
CUTOFF=$(date -v-7d +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -d '7 days ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || echo "")

STALE=""
if [[ -n "$CUTOFF" ]]; then
  STALE=$(echo "$IN_PROGRESS" | jq -r --arg cutoff "$CUTOFF" \
    '.todos[] | select(.updated_at < $cutoff) | "  [\(.uuid[:8])] \(.content) (stale since \(.updated_at[:10]))"' 2>/dev/null) || true
fi

{
  echo ""
  echo "=== doob session alert: $TODAY ==="
  if [[ -n "$OVERDUE" ]]; then
    echo "OVERDUE todos:"
    echo "$OVERDUE"
  fi
  if [[ -n "$STALE" ]]; then
    echo "STALE in-progress todos (>7 days):"
    echo "$STALE"
  fi
  if [[ -z "$OVERDUE" && -z "$STALE" ]]; then
    echo "No overdue or stale todos."
  fi
  echo "==================================="
  echo ""
} >> "$LOG"

exit 0
