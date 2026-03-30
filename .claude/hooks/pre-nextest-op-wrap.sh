#!/usr/bin/env bash
# pre-nextest-op-wrap.sh — PreToolUse hook (Bash)
# Rewrites `cargo nextest` commands to prepend _DEVLOOP_OP_WRAPPED=1
# if not already present. Prevents 1Password prompts during test runs.

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only act on cargo nextest commands
[[ "$CMD" == *"cargo nextest"* ]] || exit 0

# Only act if _DEVLOOP_OP_WRAPPED is not already set
[[ "$CMD" == *"_DEVLOOP_OP_WRAPPED"* ]] && exit 0

# Check if we're in a devloop-family project (has crates/ directory)
# to avoid false positives on other Rust projects
PWD_CHECK=$(pwd)
if [[ ! -d "$PWD_CHECK/crates" ]]; then
  # Also check if the command references devloop as a standalone path component
  [[ "$CMD" =~ (^|/)devloop(/|$) ]] || exit 0
fi

# Rewrite the command to prepend the env var
NEW_CMD="_DEVLOOP_OP_WRAPPED=1 $CMD"

# Output the modified command in Claude Code PreToolUse rewrite format
echo "{\"type\": \"rewrite\", \"updatedInput\": {\"command\": $(echo "$NEW_CMD" | jq -Rs .)}}"

exit 0
