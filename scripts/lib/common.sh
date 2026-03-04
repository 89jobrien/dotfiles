#!/usr/bin/env bash
# Common utility functions for dotfiles bootstrap scripts.
# Source this file after log.sh and cmd.sh.
#
# Usage:
#   source "${ROOT_DIR}/scripts/lib/log.sh"
#   source "${ROOT_DIR}/scripts/lib/cmd.sh"
#   source "${ROOT_DIR}/scripts/lib/common.sh"
#   TAG="my-script"
#
# Categories:
#   User Input:    prompt_value, prompt_confirm
#   Validation:    is_non_negative_int, is_empty, is_url
#   Directory:     ensure_dir, ensure_file_dir
#   Git/Repo:      clone_or_update
#   String:        trim, to_lower, to_upper

# ---------------------------------------------------------------------------
# User Input Functions
# ---------------------------------------------------------------------------

# prompt_value PROMPT [DEFAULT]
#   Prompt user for input. Uses gum if available, falls back to read.
#   Returns empty string if non-interactive or user cancels.
#   Example: name="$(prompt_value "Your name" "John Doe")"
prompt_value() {
  local prompt="$1"
  local default="${2:-}"
  local value=""

  if [[ ! -t 0 ]]; then
    echo "${default}"
    return 0
  fi

  if has_cmd gum; then
    if [[ -n "${default}" ]]; then
      value="$(gum input --placeholder "${prompt}" --value "${default}" --prompt "> " || echo "${default}")"
    else
      value="$(gum input --placeholder "${prompt}" --prompt "> " || true)"
    fi
  else
    if [[ -n "${default}" ]]; then
      read -r -p "${prompt} [${default}]: " value || true
      value="${value:-${default}}"
    else
      read -r -p "${prompt}: " value || true
    fi
  fi

  echo "${value}"
}

# prompt_confirm PROMPT [DEFAULT_YES]
#   Ask yes/no question. Returns 0 for yes, 1 for no.
#   DEFAULT_YES: if "true", defaults to yes; otherwise defaults to no.
#   Example: if prompt_confirm "Continue?" "true"; then ...
prompt_confirm() {
  local prompt="$1"
  local default_yes="${2:-false}"
  local answer=""

  if [[ ! -t 0 ]]; then
    [[ "${default_yes}" == "true" ]] && return 0 || return 1
  fi

  if has_cmd gum; then
    if gum confirm "${prompt}"; then
      return 0
    else
      return 1
    fi
  else
    local yn_prompt
    if [[ "${default_yes}" == "true" ]]; then
      yn_prompt="${prompt} [Y/n]: "
    else
      yn_prompt="${prompt} [y/N]: "
    fi

    read -r -p "${yn_prompt}" answer
    answer="$(echo "${answer}" | tr '[:upper:]' '[:lower:]')"

    if [[ -z "${answer}" ]]; then
      [[ "${default_yes}" == "true" ]] && return 0 || return 1
    fi

    [[ "${answer}" == "y" || "${answer}" == "yes" ]] && return 0 || return 1
  fi
}

# ---------------------------------------------------------------------------
# Validation Functions
# ---------------------------------------------------------------------------

# is_non_negative_int VALUE
#   Returns 0 if VALUE is a non-negative integer, 1 otherwise.
#   Example: if is_non_negative_int "${count}"; then ...
is_non_negative_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

# is_empty VALUE
#   Returns 0 if VALUE is empty or only whitespace, 1 otherwise.
#   Example: if is_empty "${name}"; then ...
is_empty() {
  local value="$1"
  value="$(echo "${value}" | tr -d '[:space:]')"
  [[ -z "${value}" ]]
}

# is_url VALUE
#   Returns 0 if VALUE looks like a URL (http/https/git), 1 otherwise.
#   Example: if is_url "${repo}"; then ...
is_url() {
  [[ "$1" =~ ^(https?|git)://.+ ]] || [[ "$1" =~ ^git@.+:.+ ]]
}

# ---------------------------------------------------------------------------
# Directory Functions
# ---------------------------------------------------------------------------

# ensure_dir DIR [MODE]
#   Create directory if it doesn't exist. Optional MODE (default: 755).
#   Example: ensure_dir "${HOME}/.config/app" "700"
ensure_dir() {
  local dir="$1"
  local mode="${2:-755}"

  if [[ ! -d "${dir}" ]]; then
    mkdir -p "${dir}"
    chmod "${mode}" "${dir}"
  fi
}

# ensure_file_dir FILE
#   Ensure the parent directory of FILE exists.
#   Example: ensure_file_dir "${HOME}/.config/app/config.json"
ensure_file_dir() {
  local file="$1"
  local dir
  dir="$(dirname "${file}")"
  ensure_dir "${dir}"
}

# ---------------------------------------------------------------------------
# Git/Repo Functions
# ---------------------------------------------------------------------------

# clone_or_update REPO_URL DEST_DIR [DEPTH]
#   Clone repo to DEST_DIR if missing, otherwise pull --ff-only.
#   Uses gh if authenticated and REPO_URL is in org/repo format.
#   DEPTH: optional clone depth (default: no --depth flag)
#   Returns 0 on success, 1 on failure.
clone_or_update() {
  local repo_url="$1"
  local dest_dir="$2"
  local depth="${3:-}"

  # Update existing repo
  if [[ -d "${dest_dir}/.git" ]]; then
    log "updating repo at ${dest_dir}..."
    if git -C "${dest_dir}" pull --ff-only; then
      log_ok "updated ${dest_dir}"
      return 0
    else
      log_warn "git pull failed; continuing with existing checkout"
      return 0
    fi
  fi

  # Clone new repo
  log "cloning ${repo_url} into ${dest_dir}..."
  ensure_dir "$(dirname "${dest_dir}")"

  local clone_args=()
  if [[ -n "${depth}" ]]; then
    clone_args+=("--depth" "${depth}")
  fi

  # Try gh clone for org/repo format if gh is authenticated
  if has_cmd gh && gh auth status -h github.com >/dev/null 2>&1; then
    if [[ "${repo_url}" == *"/"* && ! "${repo_url}" =~ ^(https?|git):// && ! "${repo_url}" =~ ^git@ ]]; then
      if gh repo clone "${repo_url}" "${dest_dir}" -- "${clone_args[@]}"; then
        log_ok "cloned ${repo_url}"
        return 0
      fi
    fi
  fi

  # Fallback to git clone
  if git clone "${repo_url}" "${dest_dir}" "${clone_args[@]}"; then
    log_ok "cloned ${repo_url}"
    return 0
  fi

  log_err "failed to clone ${repo_url}"
  return 1
}

# ---------------------------------------------------------------------------
# String Functions
# ---------------------------------------------------------------------------

# trim VALUE
#   Remove leading and trailing whitespace.
#   Example: trimmed="$(trim "  hello  ")"
trim() {
  local value="$1"
  # Remove leading whitespace
  value="${value#"${value%%[![:space:]]*}"}"
  # Remove trailing whitespace
  value="${value%"${value##*[![:space:]]}"}"
  echo "${value}"
}

# to_lower VALUE
#   Convert string to lowercase.
#   Example: lower="$(to_lower "HELLO")"
to_lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

# to_upper VALUE
#   Convert string to uppercase.
#   Example: upper="$(to_upper "hello")"
to_upper() {
  echo "$1" | tr '[:lower:]' '[:upper:]'
}
