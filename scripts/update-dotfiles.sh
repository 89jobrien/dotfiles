#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="update"

STASH_CHANGES="${STASH_CHANGES:-1}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Update dotfiles from remote repository and reload shell configuration.

Options:
  --no-stash         Don't stash local changes (fail if working tree is dirty)
  --pull-only        Only pull changes, don't reload shell
  --help             Show this help message

Environment:
  STASH_CHANGES      Stash local changes before pulling (default: 1)

Examples:
  $(basename "$0")              # Update and reload
  $(basename "$0") --no-stash   # Fail if local changes exist
  dotfiles-update               # Via alias (if configured)
EOF
}

update_dotfiles() {
  cd "$ROOT_DIR"

  section "Dotfiles Update"

  # Check if we're in a git repo
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    log_err "Not a git repository: $ROOT_DIR"
    exit 1
  fi

  # Check for local changes
  if ! git diff-index --quiet HEAD --; then
    if [[ "$STASH_CHANGES" == "1" ]]; then
      log_warn "Local changes detected, stashing..."
      git stash push -m "dotfiles-update: auto-stash $(date +%Y-%m-%d_%H:%M:%S)"
      local stashed=1
    else
      log_err "Local changes detected. Commit or stash them first, or use --stash"
      exit 1
    fi
  else
    local stashed=0
  fi

  # Pull latest changes
  log "Pulling latest changes from remote..."
  if git pull --rebase; then
    log_ok "Updated successfully"
  else
    log_err "Pull failed"
    if [[ $stashed -eq 1 ]]; then
      log "Your changes are stashed. Run 'git stash pop' to restore them."
    fi
    exit 1
  fi

  # Pop stash if we stashed
  if [[ $stashed -eq 1 ]]; then
    log "Restoring stashed changes..."
    if git stash pop; then
      log_ok "Stashed changes restored"
    else
      log_warn "Stash pop failed (conflicts?). Check 'git stash list'"
    fi
  fi

  # Clear update notification
  rm -f "${HOME}/.cache/dotfiles-update-available"

  # Show what changed
  log ""
  log "Recent commits:"
  git log --oneline -5 --decorate --color=always

  log_ok "Dotfiles updated"
}

reload_shell() {
  log ""
  log "Reload your shell to apply changes:"
  echo "  source ~/.zshrc"
  log ""
  log "Or restart your terminal"
}

main() {
  local pull_only=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-stash)
        STASH_CHANGES=0
        shift
        ;;
      --pull-only)
        pull_only=1
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

  update_dotfiles

  if [[ $pull_only -eq 0 ]]; then
    reload_shell
  fi
}

main "$@"
