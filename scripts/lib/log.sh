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
#
# Environment Variables:
#   LOG_FORMAT=json              # Enable JSON output for Vector ingestion
#   LOG_FILE=path                # Write logs to file (in addition to stdout)
#   TAG=name                     # Script identifier (required)

_LOG_HAS_GUM=0
if command -v gum >/dev/null 2>&1 && [[ -t 1 ]]; then
  _LOG_HAS_GUM=1
fi

# Log format: text (default) or json
LOG_FORMAT="${LOG_FORMAT:-text}"
LOG_FILE="${LOG_FILE:-}"

_log_fmt() {
  local color="$1" prefix="$2"
  shift 2
  local tag="${TAG:-log}"
  local level="${prefix:-info}"
  local message="$*"

  # Determine output based on format
  if [[ "${LOG_FORMAT}" == "json" ]]; then
    # JSON structured output for Vector
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
    local hostname
    hostname="$(hostname)"
    local json_line
    json_line="$(printf '{"timestamp":"%s","hostname":"%s","tag":"%s","level":"%s","message":"%s"}' \
      "${timestamp}" "${hostname}" "${tag}" "${level}" "${message}")"

    # Output to stdout
    printf '%s\n' "${json_line}"

    # Optionally write to file
    if [[ -n "${LOG_FILE}" ]]; then
      printf '%s\n' "${json_line}" >> "${LOG_FILE}"
    fi
  else
    # Text output (existing behavior)
    if [[ "${_LOG_HAS_GUM}" == "1" ]]; then
      local msg
      if [[ -n "${prefix}" ]]; then
        msg="[${tag}] ${prefix}: ${message}"
      else
        msg="[${tag}] ${message}"
      fi
      gum style --foreground "${color}" "${msg}"
    else
      if [[ -n "${prefix}" ]]; then
        printf '[%s] %s: %s\n' "${tag}" "${prefix}" "${message}"
      else
        printf '[%s] %s\n' "${tag}" "${message}"
      fi
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

# spin_with_msg MSG CMD [ARGS...]
#   Run command with a message prefix
#   Shows what's being done without suppressing output
spin_with_msg() {
  local msg="$1"
  shift
  local tag="${TAG:-log}"
  log "${msg}"
  "$@"
}

section() {
  local name="$1"
  if [[ "${LOG_FORMAT}" == "json" ]]; then
    # In JSON mode, section is just a special log message
    _log_fmt 99 "section" "${name}"
  else
    if [[ "${_LOG_HAS_GUM}" == "1" ]]; then
      printf '\n'
      gum style --bold --foreground 99 "=== ${name} ==="
    else
      printf '\n=== %s ===\n' "${name}"
    fi
  fi
}

# init_log_file PATH
#   Initialize log file for JSON output. Creates parent directory if needed.
#   Call this if you want to write logs to a file.
init_log_file() {
  local path="$1"
  local dir
  dir="$(dirname "${path}")"
  mkdir -p "${dir}"
  LOG_FILE="${path}"
  # Create or truncate the file
  : > "${LOG_FILE}"
}

# Timing helpers
_BOOTSTRAP_START_TIME=""

record_start_time() {
  _BOOTSTRAP_START_TIME="$(date +%s)"
}

get_elapsed_time() {
  if [[ -z "${_BOOTSTRAP_START_TIME}" ]]; then
    echo "0"
    return
  fi
  local end_time
  end_time="$(date +%s)"
  local elapsed=$((end_time - _BOOTSTRAP_START_TIME))
  local mins=$((elapsed / 60))
  local secs=$((elapsed % 60))
  printf '%dm %ds' "${mins}" "${secs}"
}
