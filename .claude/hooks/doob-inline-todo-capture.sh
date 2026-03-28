#!/usr/bin/env bash
# doob-inline-todo-capture.sh — PostToolUse hook (Edit|Write)
# After editing source files, scans newly added lines for TODO/FIXME comments
# and creates matching doob todos linked to the file.
# Supported: .rs .ts .js .go (// prefix), .py .sh (# prefix), .sql (-- prefix)

set -euo pipefail

command -v jq &>/dev/null || exit 0
command -v doob &>/dev/null || exit 0

INPUT=$(cat)

# Extract tool name and file path
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0

# Determine comment style based on file extension
case "$FILE_PATH" in
  *.rs|*.ts|*.js|*.go) COMMENT_STYLE="slash" ;;
  *.py|*.sh)           COMMENT_STYLE="hash"  ;;
  *.sql)               COMMENT_STYLE="dash"  ;;
  *)                   exit 0 ;;
esac

# Get the newly added content
if [[ "$TOOL" == "Edit" ]]; then
  NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
elif [[ "$TOOL" == "Write" ]]; then
  NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
else
  exit 0
fi

[[ -z "$NEW_CONTENT" ]] && exit 0

LOG="/tmp/doob-inline-todos.log"

# Log rotation: truncate to last 500 lines if over 1000 lines
if [[ -f "$LOG" ]]; then
  line_count=$(wc -l < "$LOG")
  if (( line_count > 1000 )); then
    tmp_log=$(mktemp)
    tail -n 500 "$LOG" > "$tmp_log" && mv "$tmp_log" "$LOG"
  fi
fi

# Build grep pattern for the comment style
case "$COMMENT_STYLE" in
  slash) GREP_PAT='//[[:space:]]*(TODO|FIXME):[[:space:]]*(.+)' ;;
  hash)  GREP_PAT='#[[:space:]]*(TODO|FIXME):[[:space:]]*(.+)'  ;;
  dash)  GREP_PAT='--[[:space:]]*(TODO|FIXME):[[:space:]]*(.+)' ;;
esac

# Extract TODO/FIXME lines and create doob todos
while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  MARKER=$(echo "$line" | grep -oE '(TODO|FIXME):' | tr -d ':' | head -1)
  [[ -z "$MARKER" ]] && continue

  TEXT=$(echo "$line" | sed -E "s|.*${MARKER}:[[:space:]]*||")
  TEXT=$(echo "$TEXT" | sed 's/[[:space:]]*$//')
  [[ -z "$TEXT" ]] && continue

  TAG="inline-todo"
  [[ "$MARKER" == "FIXME" ]] && TAG="inline-fixme"

  if doob todo add "$TEXT" --file "$FILE_PATH" --tags "$TAG" 2>/dev/null; then
    echo "[$(date)] Created todo from $MARKER in $FILE_PATH: $TEXT" >> "$LOG"
  fi
done < <(printf '%s\n' "$NEW_CONTENT" | grep -E "$GREP_PAT")

exit 0
