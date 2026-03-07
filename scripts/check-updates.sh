#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="updates"

CACHE_FILE="${HOME}/.cache/dotfiles-update-check"
CACHE_MAX_AGE="${DOTFILES_UPDATE_CHECK_INTERVAL:-3600}"  # Default: 1 hour
UPDATE_AVAILABLE_FILE="${HOME}/.cache/dotfiles-update-available"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Check for dotfiles updates from remote repository.

Options:
  --force            Force check even if cache is fresh
  --quiet            Only output if updates are available
  --notify           Show desktop notification if updates available
  --help             Show this help message

Environment:
  DOTFILES_UPDATE_CHECK_INTERVAL    Cache lifetime in seconds (default: 3600)

Examples:
  $(basename "$0")                  # Check for updates (respects cache)
  $(basename "$0") --force          # Force check now
  $(basename "$0") --quiet          # Silent check (for shell integration)
EOF
}

should_check() {
  if [[ ! -f "$CACHE_FILE" ]]; then
    return 0  # No cache, should check
  fi

  local cache_age
  cache_age=$(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null)))

  if [[ $cache_age -gt $CACHE_MAX_AGE ]]; then
    return 0  # Cache expired
  fi

  return 1  # Cache fresh, skip check
}

check_updates() {
  cd "$ROOT_DIR"

  # Ensure we're in a git repo
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    return 1
  fi

  # Fetch remote (quiet, timeout after 5 seconds)
  if ! timeout 5 git fetch origin --quiet 2>/dev/null; then
    # Network timeout or error, don't update cache
    return 1
  fi

  local local_commit remote_commit
  local_commit=$(git rev-parse HEAD)
  remote_commit=$(git rev-parse origin/main 2>/dev/null || git rev-parse origin/master 2>/dev/null)

  # Update cache timestamp
  mkdir -p "$(dirname "$CACHE_FILE")"
  date +%s > "$CACHE_FILE"

  if [[ "$local_commit" != "$remote_commit" ]]; then
    # Updates available
    echo "1" > "$UPDATE_AVAILABLE_FILE"
    return 0
  else
    # No updates
    rm -f "$UPDATE_AVAILABLE_FILE"
    return 1
  fi
}

show_update_message() {
  local local_commit remote_commit commits_behind

  cd "$ROOT_DIR"

  local_commit=$(git rev-parse --short HEAD)
  remote_commit=$(git rev-parse --short origin/main 2>/dev/null || git rev-parse --short origin/master 2>/dev/null)
  commits_behind=$(git rev-list --count HEAD..origin/main 2>/dev/null || git rev-list --count HEAD..origin/master 2>/dev/null)

  cat <<EOF

╭─────────────────────────────────────────────────────────╮
│  Dotfiles updates available!                            │
│                                                          │
│  Local:  $local_commit                                           │
│  Remote: $remote_commit                                           │
│  Behind: $commits_behind commits                                  │
│                                                          │
│  Update: cd ~/dotfiles && git pull && source ~/.zshrc   │
│  Or run: dotfiles-update                                 │
╰─────────────────────────────────────────────────────────╯

EOF
}

send_notification() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return  # macOS only for now
  fi

  local commits_behind
  commits_behind=$(git -C "$ROOT_DIR" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")

  osascript -e "display notification \"$commits_behind commits behind remote\" with title \"Dotfiles Updates Available\" sound name \"Glass\"" 2>/dev/null || true
}

main() {
  local force=0
  local quiet=0
  local notify=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)
        force=1
        shift
        ;;
      --quiet)
        quiet=1
        shift
        ;;
      --notify)
        notify=1
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

  # Check cache unless forced
  if [[ $force -eq 0 ]] && ! should_check; then
    # Cache is fresh, check if updates were previously detected
    if [[ -f "$UPDATE_AVAILABLE_FILE" ]] && [[ $quiet -eq 0 ]]; then
      show_update_message
    fi
    return 0
  fi

  # Run the check (in background to avoid blocking shell startup)
  if check_updates; then
    # Updates available
    if [[ $quiet -eq 0 ]]; then
      show_update_message
    fi

    if [[ $notify -eq 1 ]]; then
      send_notification
    fi
  else
    # No updates or check failed
    if [[ $quiet -eq 0 ]]; then
      log_ok "Dotfiles are up to date"
    fi
  fi
}

main "$@"
