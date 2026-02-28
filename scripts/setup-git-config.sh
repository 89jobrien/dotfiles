#!/usr/bin/env bash
set -euo pipefail

log() {
  if command -v gum >/dev/null 2>&1 && [[ -t 1 ]]; then
    gum style --foreground 212 "[git-config] $*"
  else
    printf '[git-config] %s\n' "$*"
  fi
}

get_gh_field() {
  local field="$1"
  if ! command -v gh >/dev/null 2>&1; then
    echo ""
    return 0
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo ""
    return 0
  fi
  gh api user -q "${field}" 2>/dev/null || echo ""
}

prompt_value() {
  local label="$1"
  local value=""
  if [[ ! -t 0 ]]; then
    echo ""
    return 0
  fi

  if command -v gum >/dev/null 2>&1; then
    value="$(gum input --placeholder "${label}" --prompt "> " || true)"
  else
    read -r -p "${label}: " value || true
  fi
  echo "${value}"
}

main() {
  local current_name current_email
  current_name="$(git config --global --get user.name || true)"
  current_email="$(git config --global --get user.email || true)"

  if [[ -n "${current_name}" && -n "${current_email}" ]]; then
    log "Global git identity already configured (${current_name} <${current_email}>)."
    return 0
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
    log "Set git user.name=${desired_name}"
  fi

  if [[ -z "${current_email}" && -n "${desired_email}" ]]; then
    git config --global user.email "${desired_email}"
    log "Set git user.email=${desired_email}"
  fi

  current_name="$(git config --global --get user.name || true)"
  current_email="$(git config --global --get user.email || true)"
  if [[ -z "${current_name}" || -z "${current_email}" ]]; then
    log "Git identity is still incomplete."
    log "Set it manually with:"
    log "  git config --global user.name \"Your Name\""
    log "  git config --global user.email \"you@example.com\""
  fi
}

main "$@"
