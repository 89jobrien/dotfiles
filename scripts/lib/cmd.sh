#!/usr/bin/env bash
# Command availability checking utilities for dotfiles bootstrap scripts.
# Source this file after log.sh.
#
# Usage:
#   source "${ROOT_DIR}/scripts/lib/log.sh"
#   source "${ROOT_DIR}/scripts/lib/cmd.sh"
#   TAG="my-script"
#
#   has_cmd git                    # returns 0 if git exists, 1 otherwise
#   require_cmd git "brew install git"  # exits if git missing
#   check_cmd git                  # logs ok/error, sets global status
#   check_optional_cmd zed         # logs ok/skip for optional commands

# has_cmd CMD
#   Silent check: returns 0 if command exists, 1 otherwise
has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# find_cmd CMD
#   Return the path to CMD if it exists, empty string otherwise
find_cmd() {
  command -v "$1" 2>/dev/null || true
}

# require_cmd CMD [INSTALL_HINT]
#   Exit with error if CMD is not found. Optional hint for installation.
require_cmd() {
  local cmd="$1"
  local hint="${2:-}"
  if ! has_cmd "${cmd}"; then
    log_err "missing required command: ${cmd}"
    if [[ -n "${hint}" ]]; then
      log "install: ${hint}"
    fi
    exit 1
  fi
}

# check_cmd CMD [STATUS_VAR]
#   Check if CMD exists, log ok/error. If STATUS_VAR provided, set it to 1 on failure.
#   Designed for doctor-style health checks.
check_cmd() {
  local cmd="$1"
  local status_var="${2:-status}"
  if has_cmd "${cmd}"; then
    log_ok "${cmd} -> $(command -v "${cmd}")"
  else
    log_err "${cmd} missing"
    eval "${status_var}=1"
  fi
}

# check_optional_cmd CMD
#   Check if CMD exists, log ok/skip. Never sets error status.
check_optional_cmd() {
  local cmd="$1"
  if has_cmd "${cmd}"; then
    log_ok "${cmd} -> $(command -v "${cmd}")"
  else
    log_skip "${cmd} (optional)"
  fi
}

# ensure_cmd CMD INSTALL_CMD [FAILED_ARRAY]
#   Check if CMD exists. If not, run INSTALL_CMD to install it.
#   Optionally append to FAILED_ARRAY on install failure.
#   Returns 0 if command exists or install succeeds, 1 if install fails.
ensure_cmd() {
  local cmd="$1"
  local install_cmd="$2"
  local failed_array="${3:-}"

  if has_cmd "${cmd}"; then
    return 0
  fi

  log "installing ${cmd}..."
  if ! eval "${install_cmd}"; then
    log_warn "failed to install ${cmd}; continuing"
    if [[ -n "${failed_array}" ]]; then
      eval "${failed_array}+=(\"${cmd}\")"
    fi
    return 1
  fi

  return 0
}
