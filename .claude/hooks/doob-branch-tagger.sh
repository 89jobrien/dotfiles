#!/usr/bin/env bash
# doob-branch-tagger.sh — PreToolUse hook
# Rewrites `doob todo add <text>` to inject --tags <branch> when on a feature/fix/chore branch.
# Only triggers if the command doesn't already contain --tags.

set -euo pipefail

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$CMD" ]] && exit 0

# Only act on doob todo add commands
[[ "$CMD" == *"doob todo add"* ]] || exit 0

# Skip if already has --tags
[[ "$CMD" == *"--tags"* ]] && exit 0

# Detect git branch
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0

# Only tag on feature/fix/chore branches
[[ "$BRANCH" =~ ^(feature|fix|chore|feat)/ ]] || exit 0

# Extract slug (strip prefix, replace / and _ with -)
SLUG=$(echo "$BRANCH" | sed 's|^[^/]*/||' | tr '/_' '--' | tr '[:upper:]' '[:lower:]')

# Append --tags to the command
REWRITTEN="${CMD} --tags ${SLUG}"

ORIGINAL_INPUT=$(echo "$INPUT" | jq -c '.tool_input')
UPDATED_INPUT=$(echo "$ORIGINAL_INPUT" | jq --arg cmd "$REWRITTEN" '.command = $cmd')

jq -n \
  --argjson updated "$UPDATED_INPUT" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "allow",
      "permissionDecisionReason": "doob-branch-tagger: injected --tags from branch",
      "updatedInput": $updated
    }
  }'
