#!/usr/bin/env bash
# pre-commit-todo-remind.sh — PreToolUse hook (Bash)
# Before git commit, checks for in-progress doob todos and reminds to
# include "closes <uuid>" in the commit message for auto-completion.
# Complements doob-commit-autocomplete.sh which processes AFTER the commit.

set -euo pipefail

command -v doob &>/dev/null || exit 0
command -v jq &>/dev/null || exit 0

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only act on git commit commands (not git commit --amend without -m, etc.)
[[ "$CMD" == *"git commit"* ]] || exit 0

# Skip if commit message already contains closes/fixes/resolves
if echo "$CMD" | grep -qiE "(closes?|fixes?|resolves?) [0-9a-f]{8}-"; then
  exit 0
fi

# Get in-progress todos
UUID_PAT='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
IN_PROGRESS=$(doob todo list 2>/dev/null | grep -i "in.progress\|in_progress\|started" | head -5)

[[ -z "$IN_PROGRESS" ]] && exit 0

echo ""
echo "📋 In-progress todos (add 'closes <uuid>' to auto-complete):"
echo "$IN_PROGRESS" | while IFS= read -r line; do
  UUID=$(echo "$line" | grep -oE "$UUID_PAT" | head -1)
  if [[ -n "$UUID" ]]; then
    DESC=$(echo "$line" | sed "s/$UUID//" | sed 's/^[ \t]*//' | cut -c1-60)
    echo "  $UUID  $DESC"
  fi
done

exit 0
