#!/usr/bin/env bash
# generate-summary.sh
# Generates a Pieces workstream summary and appends it to the Obsidian vault.
# Run via cron on the rentamac or m5-max.
#
# Usage: bash generate-summary.sh [standup|recap|topofmind]
# Cron example (daily 6am standup, 6pm recap):
#   0 6  * * * bash ~/scripts/generate-summary.sh standup
#   0 18 * * * bash ~/scripts/generate-summary.sh recap

set -euo pipefail

PIECES_URL="http://localhost:39300"
VAULT_DIR="${VAULT_DIR:-$HOME/Documents/ObsidianVault}"
SUMMARY_DIR="$VAULT_DIR/01_Daily"
TYPE="${1:-standup}"
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M)

# Map type to prompt
case "$TYPE" in
  standup)   PROMPT="Generate a standup update: what was worked on yesterday, what's planned today, any blockers." ;;
  recap)     PROMPT="Generate a day recap: summary of everything worked on today, decisions made, and next steps." ;;
  topofmind) PROMPT="What's currently top of mind based on recent activity? Summarize key focus areas." ;;
  *)         PROMPT="$TYPE" ;;
esac

echo "Generating $TYPE summary via PiecesOS..."

# Call PiecesOS workstream summary endpoint
RESPONSE=$(curl -sf -X POST \
  "$PIECES_URL/workstream_summaries/create" \
  -H "Content-Type: application/json" \
  -d "{\"seed\": {\"type\": \"WORKSTREAM_PATTERN_ENGINE_SEED_TYPE_DAILY\"}}" \
  2>/dev/null) || true

# Fallback: use the /qgpt/question endpoint with LTM context
if [ -z "$RESPONSE" ]; then
  RESPONSE=$(curl -sf -X POST \
    "$PIECES_URL/qgpt/question" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"$PROMPT\", \"relevant\": {\"iterable\": []}, \"pipeline\": {\"conversation\": {\"contextualized_code_dialog\": {}}}}" \
    2>/dev/null) || true
fi

if [ -z "$RESPONSE" ]; then
  echo "✗ No response from PiecesOS at $PIECES_URL"
  exit 1
fi

# Extract text from response
SUMMARY=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # Try workstream summary path
    text = d.get('summary', {}).get('raw', '') or \
           d.get('answers', {}).get('iterable', [{}])[0].get('text', '') or \
           str(d)
    print(text.strip())
except Exception as e:
    print(sys.stdin.read())
" 2>/dev/null || echo "$RESPONSE")

# Target file: today's daily note
NOTE_FILE="$SUMMARY_DIR/${DATE}.md"

# Append to daily note if it exists, otherwise create a standalone summary
if [ -f "$NOTE_FILE" ]; then
  cat >> "$NOTE_FILE" << EOF

## Pieces $TYPE — $TIME

$SUMMARY
EOF
  echo "✓ Appended to $NOTE_FILE"
else
  # Save as standalone summary note
  SUMMARY_FILE="$VAULT_DIR/00_Inbox/pieces-${TYPE}-${DATE}-${TIME//:/}.md"
  cat > "$SUMMARY_FILE" << EOF
---
type: summary
date: $DATE
time: $TIME
summary_type: $TYPE
source: pieces-ltm
---

# Pieces $TYPE — $DATE $TIME

$SUMMARY
EOF
  echo "✓ Saved to $SUMMARY_FILE"
fi
