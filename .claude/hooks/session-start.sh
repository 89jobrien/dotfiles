#!/usr/bin/env bash
# session-start.sh — Emits a navigator hint when starting a session in any ~/dev/* project.
# SessionStart hook stdout IS shown to users as a context message.

CWD=$(pwd)
DEV_DIR="$HOME/dev"

# Check if CWD is inside ~/dev/<project> and extract the project name.
if [[ "$CWD" == "$DEV_DIR/"* ]]; then
  remainder="${CWD#"$DEV_DIR/"}"
  project="${remainder%%/*}"
  if [ -n "$project" ]; then
    echo "Navigator available: run /navigate $project for an architecture briefing."
  fi
fi

# Run rtk learn in the background — mines Claude Code error history for corrections.
if command -v rtk &>/dev/null; then
  rtk learn --quiet 2>/dev/null &
fi

exit 0
