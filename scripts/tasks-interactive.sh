#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="tasks"

TASKS_CACHE="/tmp/dotfiles-tasks-cache.txt"
RUNNER="${TASKS_RUNNER:-auto}"

# Check for required tools
require_cmd fzf

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Interactive task discovery and execution for dotfiles.

Options:
  --mise             Use mise tasks only
  --just             Use just recipes only
  --list             List all tasks without running fzf
  --help             Show this help message

Environment:
  TASKS_RUNNER       Preferred runner (mise, just, auto)

Examples:
  $(basename "$0")           # Interactive fzf selection
  $(basename "$0") --list    # Show all tasks
  tasks                      # Via alias (if configured)
EOF
}

parse_mise_tasks() {
  local mise_file="${ROOT_DIR}/.mise.toml"
  if [[ ! -f "$mise_file" ]]; then
    return
  fi

  # Parse mise tasks from .mise.toml using sed/grep (BSD-compatible)
  grep -A 1 '^\[tasks\.' "$mise_file" | grep -v '^--$' | while read -r line; do
    if [[ "$line" =~ ^\[tasks\.([^]]+)\] ]]; then
      task="${BASH_REMATCH[1]}"
      # Read next line for description
      read -r next_line
      if [[ "$next_line" =~ description\ =\ \"([^\"]+)\" ]]; then
        desc="${BASH_REMATCH[1]}"
        printf "mise run %-30s # %s\n" "$task" "$desc"
      else
        printf "mise run %-30s\n" "$task"
      fi
    fi
  done
}

parse_just_recipes() {
  local justfile="${ROOT_DIR}/Justfile"
  if [[ ! -f "$justfile" ]]; then
    return
  fi

  # Parse just recipes using grep and bash regex
  grep '^[a-z][a-zA-Z0-9_-]*:' "$justfile" | while read -r line; do
    # Extract recipe name (before colon)
    if [[ "$line" =~ ^([a-z][a-zA-Z0-9_-]*): ]]; then
      recipe="${BASH_REMATCH[1]}"

      # Check for inline comment
      if [[ "$line" =~ \#(.+)$ ]]; then
        comment="${BASH_REMATCH[1]}"
        comment="${comment#"${comment%%[![:space:]]*}"}"  # Trim leading spaces
        printf "just %-30s # %s\n" "$recipe" "$comment"
      else
        printf "just %-30s\n" "$recipe"
      fi
    fi
  done
}

generate_task_list() {
  {
    if [[ "$RUNNER" == "mise" ]] || [[ "$RUNNER" == "auto" ]]; then
      parse_mise_tasks
    fi

    if [[ "$RUNNER" == "just" ]] || [[ "$RUNNER" == "auto" ]]; then
      parse_just_recipes
    fi
  } | sort -u
}

run_interactive() {
  local selected

  # Generate task list
  generate_task_list > "$TASKS_CACHE"

  # Use fzf for selection
  selected=$(cat "$TASKS_CACHE" | fzf \
    --height 40% \
    --reverse \
    --border \
    --prompt "Select task > " \
    --preview 'echo {}' \
    --preview-window=up:3:wrap \
    --header="Use ↑↓ to navigate, Enter to run, Esc to cancel" \
    || true)

  if [[ -z "$selected" ]]; then
    log "No task selected"
    return 0
  fi

  # Extract command (everything before the # comment)
  local cmd
  cmd=$(echo "$selected" | sed 's/#.*//' | xargs)

  log "Running: $cmd"
  echo ""

  # Execute the command
  eval "$cmd"
}

list_tasks() {
  generate_task_list
}

main() {
  local mode="interactive"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mise)
        RUNNER="mise"
        shift
        ;;
      --just)
        RUNNER="just"
        shift
        ;;
      --list)
        mode="list"
        shift
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        log_err "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done

  case "$mode" in
    interactive)
      run_interactive
      ;;
    list)
      list_tasks
      ;;
  esac
}

main "$@"
