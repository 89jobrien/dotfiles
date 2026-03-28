#!/usr/bin/env bash
# post-push-ci-watch.sh — PostToolUse hook (Bash)
# After git push, looks up the CI run for the pushed branch and reports
# the run URL + status. Saves the "check the CI → find the URL" lookup.

set -euo pipefail

command -v gh &>/dev/null || exit 0
command -v jq &>/dev/null || exit 0

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only act on git push commands
[[ "$CMD" == *"git push"* ]] || exit 0

# Get current branch
BRANCH=$(git branch --show-current 2>/dev/null)
[[ -n "$BRANCH" ]] || exit 0

# Poll up to 5 times with 2s between attempts to let GitHub register the push
RUN_INFO=""
for attempt in 1 2 3 4 5; do
  sleep 2
  RUN_INFO=$(gh run list \
    --branch "$BRANCH" \
    --limit 1 \
    --json databaseId,status,conclusion,name,url,updatedAt \
    2>/dev/null) || true
  RUN_COUNT=$(echo "$RUN_INFO" | jq 'length' 2>/dev/null || echo 0)
  [[ "$RUN_COUNT" -gt 0 ]] && break
  RUN_INFO=""
done

[[ -n "$RUN_INFO" ]] || exit 0
RUN_COUNT=$(echo "$RUN_INFO" | jq 'length' 2>/dev/null || echo 0)
[[ "$RUN_COUNT" -gt 0 ]] || exit 0

RUN_ID=$(echo "$RUN_INFO" | jq -r '.[0].databaseId')
RUN_STATUS=$(echo "$RUN_INFO" | jq -r '.[0].status')
RUN_CONCLUSION=$(echo "$RUN_INFO" | jq -r '.[0].conclusion // ""')
RUN_URL=$(echo "$RUN_INFO" | jq -r '.[0].url')

echo ""
if [[ "$RUN_STATUS" == "completed" ]]; then
  if [[ "$RUN_CONCLUSION" == "success" ]]; then
    echo "[ok] CI ($BRANCH): $RUN_CONCLUSION -- $RUN_URL"
  else
    echo "[fail] CI ($BRANCH): $RUN_CONCLUSION -- $RUN_URL"
  fi
else
  echo "[running] CI ($BRANCH): $RUN_STATUS -- $RUN_URL"
  echo "   Watch: gh run watch $RUN_ID"
fi

exit 0
