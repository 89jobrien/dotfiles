#!/usr/bin/env bash
# Shared logging library for dotfiles bootstrap scripts.
# Source this file and set TAG="script-name" before calling any function.
#
# Usage:
#   source "${ROOT_DIR}/scripts/lib/log.sh"
#   TAG="my-script"
#   log "doing something"        # [my-script] doing something
#   log_ok "all good"            # [my-script] ok: all good
#   log_skip "not needed"        # [my-script] skip: not needed
#   log_warn "heads up"          # [my-script] warn: heads up
#   log_err "broken"             # [my-script] err: broken
#   spin "compiling" make build  # gum spinner or inline fallback
#   section "Section Name"       # === Section Name ===

_LOG_HAS_GUM=0
if command -v gum >/dev/null 2>&1 && [[ -t 1 ]]; then
  _LOG_HAS_GUM=1
fi

_log_fmt() {
  local color="$1" prefix="$2"
  shift 2
  local tag="${TAG:-log}"
  if [[ "${_LOG_HAS_GUM}" == "1" ]]; then
    local msg
    if [[ -n "${prefix}" ]]; then
      msg="[${tag}] ${prefix}: $*"
    else
      msg="[${tag}] $*"
    fi
    gum style --foreground "${color}" "${msg}"
  else
    if [[ -n "${prefix}" ]]; then
      printf '[%s] %s: %s\n' "${tag}" "${prefix}" "$*"
    else
      printf '[%s] %s\n' "${tag}" "$*"
    fi
  fi
}

log()      { _log_fmt 212 "" "$@"; }
log_ok()   { _log_fmt 10  "ok" "$@"; }
log_skip() { _log_fmt 245 "skip" "$@"; }
log_warn() { _log_fmt 214 "warn" "$@"; }
log_err()  { _log_fmt 196 "err" "$@"; }

spin() {
  local msg="$1"
  shift
  local tag="${TAG:-log}"
  if [[ "${_LOG_HAS_GUM}" == "1" ]]; then
    gum spin --title "[${tag}] ${msg}" -- "$@"
  else
    log "${msg}"
    "$@"
  fi
}

section() {
  local name="$1"
  if [[ "${_LOG_HAS_GUM}" == "1" ]]; then
    printf '\n'
    gum style --bold --foreground 99 "=== ${name} ==="
  else
    printf '\n=== %s ===\n' "${name}"
  fi
}
