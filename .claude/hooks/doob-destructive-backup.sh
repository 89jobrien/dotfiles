#!/usr/bin/env bash
# doob-destructive-backup.sh — PreToolUse hook (Bash)
# Before `doob todo remove` or `doob note remove`, backs up the SurrealDB database.
# Keeps the 10 most recent backups.

set -euo pipefail

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only act on destructive doob operations
[[ "$CMD" == *"doob todo remove"* ]] || [[ "$CMD" == *"doob note remove"* ]] || exit 0

DB_PATH="${DOOB_DB_PATH:-$HOME/.claude/data/doob.db}"
BACKUP_DIR="$HOME/.doob/backups"

# Skip if DB doesn't exist yet
[[ -e "$DB_PATH" ]] || exit 0

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="$BACKUP_DIR/doob-${TIMESTAMP}.db"

cp -r "$DB_PATH" "$BACKUP_PATH"

# Trim to 10 most recent backups
ls -t "$BACKUP_DIR"/doob-*.db 2>/dev/null | tail -n +11 | xargs rm -rf 2>/dev/null || true

LOG="/tmp/doob-backup.log"
echo "[$(date)] Backup created: $BACKUP_PATH (command: $CMD)" >> "$LOG"

exit 0
