#!/usr/bin/env bash
# doob-commit-autocomplete.sh — PostToolUse hook (Bash)
# After a git commit, reads the commit message from git log and checks for
# "closes <uuid>", "fixes <uuid>", "resolves <uuid>" patterns, then marks
# matching doob todos as completed.

set -euo pipefail

command -v jq &>/dev/null || exit 0
command -v doob &>/dev/null || exit 0

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
EXIT_CODE=$(echo "$INPUT" | jq -r '.exit_code // empty')

# Only act on git commit commands that succeeded
[[ "$CMD" == *"git commit"* ]] || exit 0
[[ "$EXIT_CODE" == "0" ]] || exit 0

# Read the commit message from git log (reliable regardless of how the commit was made)
MSG=$(git log -1 --format=%B 2>/dev/null) || exit 0

[[ -z "$MSG" ]] && exit 0

# Find UUIDs preceded by closes/fixes/resolves (case-insensitive)
UUID_PAT='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
UUIDS=$(echo "$MSG" \
  | grep -oiE "(closes?|fixes?|resolves?) +${UUID_PAT}" \
  | grep -oE "${UUID_PAT}")

[[ -z "$UUIDS" ]] && exit 0

LOG="/tmp/doob-commit-autocomplete.log"

# Log rotation: truncate to last 500 lines if file exceeds 1000 lines
if [[ -f "$LOG" ]]; then
  line_count=$(wc -l < "$LOG")
  if (( line_count > 1000 )); then
    tmp=$(mktemp)
    tail -n 500 "$LOG" > "$tmp" && mv "$tmp" "$LOG"
  fi
fi

while IFS= read -r uuid; do
  if doob todo complete "$uuid" 2>/dev/null; then
    echo "[$(date)] Completed todo $uuid from commit" >> "$LOG"
  else
    echo "[$(date)] Could not complete todo $uuid (not found or already complete)" >> "$LOG"
  fi
done <<< "$UUIDS"

exit 0
