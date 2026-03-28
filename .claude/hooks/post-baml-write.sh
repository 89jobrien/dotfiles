#!/usr/bin/env bash
# post-baml-write.sh — PostToolUse hook (Edit|Write)
# After editing a .baml file, runs cargo check -p devloop-baml to catch schema errors early.
# Prevents "analyze with broken schema → confusing output" failure mode.

set -euo pipefail

INPUT=$(cat)

# Extract file path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only act on .baml files
[[ "$FILE_PATH" == *.baml ]] || exit 0

# Find the devloop workspace root (look for Cargo.toml with [workspace])
SEARCH_DIR=$(dirname "$FILE_PATH")
WORKSPACE_ROOT=""
while [[ "$SEARCH_DIR" != "/" ]]; do
  if [[ -f "$SEARCH_DIR/Cargo.toml" ]] && grep -q '\[workspace\]' "$SEARCH_DIR/Cargo.toml" 2>/dev/null; then
    WORKSPACE_ROOT="$SEARCH_DIR"
    break
  fi
  SEARCH_DIR=$(dirname "$SEARCH_DIR")
done

[[ -n "$WORKSPACE_ROOT" ]] || exit 0

# Only act if devloop-baml crate exists
[[ -d "$WORKSPACE_ROOT/crates/baml" ]] || exit 0

# Run cargo check quietly — only surface errors
ERRORS=$(cd "$WORKSPACE_ROOT" && cargo check -p devloop-baml 2>&1 | grep -E "^error" | head -5)

if [[ -n "$ERRORS" ]]; then
  echo ""
  echo "⚠ BAML compile check failed after editing $(basename "$FILE_PATH"):"
  echo "$ERRORS"
  echo "Fix schema errors before running devloop analyze."
fi

exit 0
