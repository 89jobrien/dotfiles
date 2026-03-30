#!/usr/bin/env bash
# post-nextest-snap-notify.sh — PostToolUse hook (Bash)
# After a successful cargo nextest run, checks for pending .snap.new files
# and notifies if any are found. Guards against the stale-snapshot footgun.

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // 1' 2>/dev/null)

# Only act on cargo nextest commands
[[ "$CMD" == *"cargo nextest"* ]] || exit 0

# Only act on successful runs (exit code 0)
[[ "$EXIT_CODE" == "0" ]] || exit 0

# Find .snap.new files (exclude target/ to avoid false positives)
SNAP_FILES=$(find . -name "*.snap.new" -not -path "*/target/*" 2>/dev/null)

[[ -z "$SNAP_FILES" ]] && exit 0

# Count them
COUNT=$(echo "$SNAP_FILES" | wc -l | tr -d ' ')

echo ""
echo "📸 $COUNT snapshot update(s) pending after nextest:"
echo "$SNAP_FILES" | sed 's|^\./||' | sed 's/^/  /'
echo ""
echo "Review with: rust-snapshot-review skill"
echo "Quick accept: for f in \$(find . -name '*.snap.new' -not -path '*/target/*'); do mv \"\$f\" \"\${f%.new}\"; done"

exit 0
