#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="companion-repos"

# ---------------------------------------------------------------------------
# Companion repos to clone on a fresh machine.
# Each entry: "target_dir  github_owner/repo"
# ---------------------------------------------------------------------------

REPOS=(
  "$HOME/dev/personal-mcp  89jobrien/personal-mcp"
  "$HOME/dev/dumcp          89jobrien/dumcp"
  "$HOME/dev/obfsck         89jobrien/obfsck"
  "$HOME/maestro-dev        89jobrien/maestro-dev"
)

# ---------------------------------------------------------------------------

clone_repo() {
  local target="$1" repo="$2"

  if [[ -d "${target}/.git" ]]; then
    log_skip "${repo} already cloned at ${target}"
    return 0
  fi

  if [[ -d "${target}" ]]; then
    log_warn "${target} exists but is not a git repo; skipping"
    return 0
  fi

  if ! has_cmd gh; then
    log_err "gh CLI not found; cannot clone ${repo}"
    return 1
  fi

  # Verify we have access (private repos need auth)
  if ! gh repo view "${repo}" --json name >/dev/null 2>&1; then
    log_warn "cannot access ${repo} (not authenticated or repo missing); skipping"
    return 0
  fi

  local parent_dir
  parent_dir="$(dirname "${target}")"
  mkdir -p "${parent_dir}"

  log "cloning ${repo} → ${target}..."
  gh repo clone "${repo}" "${target}"
  log_ok "${repo} cloned"
}

main() {
  for entry in "${REPOS[@]}"; do
    # Split on whitespace
    local target repo
    target="$(echo "${entry}" | awk '{print $1}')"
    repo="$(echo "${entry}" | awk '{print $2}')"
    clone_repo "${target}" "${repo}"
  done
}

main
