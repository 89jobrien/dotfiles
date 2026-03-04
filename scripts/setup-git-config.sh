#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
source "${ROOT_DIR}/scripts/lib/common.sh"
TAG="git-config"

get_gh_field() {
  local field="$1"
  if ! has_cmd gh; then
    echo ""
    return 0
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo ""
    return 0
  fi
  gh api user -q "${field}" 2>/dev/null || echo ""
}

main() {
  local current_name current_email
  current_name="$(git config --global --get user.name || true)"
  current_email="$(git config --global --get user.email || true)"

  if [[ -n "${current_name}" && -n "${current_email}" ]]; then
    log_ok "identity configured (${current_name} <${current_email}>)"
  fi

  local gh_login gh_name gh_email
  gh_login="$(get_gh_field '.login // ""')"
  gh_name="$(get_gh_field '.name // ""')"
  gh_email="$(get_gh_field '.email // ""')"

  if [[ -z "${gh_name}" ]]; then
    gh_name="${gh_login}"
  fi
  if [[ -z "${gh_email}" && -n "${gh_login}" ]]; then
    gh_email="${gh_login}@users.noreply.github.com"
  fi

  local desired_name desired_email
  desired_name="${GIT_USER_NAME:-${gh_name}}"
  desired_email="${GIT_USER_EMAIL:-${gh_email}}"

  if [[ -z "${current_name}" && -z "${desired_name}" ]]; then
    desired_name="$(prompt_value "Git user.name (e.g. Jane Doe)")"
  fi
  if [[ -z "${current_email}" && -z "${desired_email}" ]]; then
    desired_email="$(prompt_value "Git user.email (e.g. jane@example.com)")"
  fi

  if [[ -z "${current_name}" && -n "${desired_name}" ]]; then
    git config --global user.name "${desired_name}"
    log "set git user.name=${desired_name}"
  fi

  if [[ -z "${current_email}" && -n "${desired_email}" ]]; then
    git config --global user.email "${desired_email}"
    log "set git user.email=${desired_email}"
  fi

  current_name="$(git config --global --get user.name || true)"
  current_email="$(git config --global --get user.email || true)"
  if [[ -z "${current_name}" || -z "${current_email}" ]]; then
    log_warn "git identity is still incomplete"
    log "set it manually with:"
    log "  git config --global user.name \"Your Name\""
    log "  git config --global user.email \"you@example.com\""
  fi

  # Prefer GitHub CLI credential flow for github.com remotes.
  if has_cmd gh; then
    if gh auth status >/dev/null 2>&1; then
      gh auth setup-git >/dev/null 2>&1 || true
      git config --global --unset-all credential.https://github.com.helper >/dev/null 2>&1 || true
      git config --global --unset-all credential.https://gist.github.com.helper >/dev/null 2>&1 || true
      git config --global --add credential.https://github.com.helper "!$(find_cmd gh) auth git-credential"
      git config --global --add credential.https://gist.github.com.helper "!$(find_cmd gh) auth git-credential"
      log_ok "configured git to use gh credentials for github.com remotes"
    else
      log_warn "gh is installed but not authenticated; skipping git credential helper setup"
      log "run: gh auth login -h github.com && gh auth setup-git"
    fi
  fi

  # Sensible push/pull defaults.
  git config --global push.autoSetupRemote true
  git config --global push.default current
  git config --global fetch.prune true
  log_ok "set git defaults: push.autoSetupRemote=true push.default=current fetch.prune=true"
}

main "$@"
