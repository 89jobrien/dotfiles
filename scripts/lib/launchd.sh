#!/usr/bin/env bash
# LaunchDaemon/LaunchAgent utilities for macOS service management.
# Source this file after log.sh.
#
# Required variables (set before calling functions):
#   LABEL        - Reverse DNS label (e.g., "com.user.service")
#   PLIST_PATH   - Path to plist file
#   DOMAIN       - launchd domain (e.g., "gui/${UID}")
#
# Optional variables (for do_logs):
#   STATE_DIR    - Directory for logs
#   STDOUT_LOG   - Path to stdout log
#   STDERR_LOG   - Path to stderr log
#
# Usage:
#   source "${ROOT_DIR}/scripts/lib/log.sh"
#   source "${ROOT_DIR}/scripts/lib/launchd.sh"
#   TAG="my-service"
#
#   LABEL="com.user.myservice"
#   DOMAIN="gui/${UID}"
#   PLIST_PATH="${HOME}/Library/LaunchAgents/${LABEL}.plist"
#
#   launchd_is_loaded && echo "Service is running"
#   launchd_uninstall
#   launchd_status

# launchd_is_loaded
#   Returns 0 if service is loaded in launchd, 1 otherwise
launchd_is_loaded() {
  launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1
}

# launchd_uninstall
#   Stop service if running and remove plist file
launchd_uninstall() {
  if launchd_is_loaded; then
    launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
  fi
  if [[ -f "${PLIST_PATH}" ]]; then
    rm -f "${PLIST_PATH}"
  fi
  log_ok "uninstalled ${LABEL}"
}

# launchd_status
#   Print service status, exit 1 if not loaded
launchd_status() {
  if launchd_is_loaded; then
    launchctl print "${DOMAIN}/${LABEL}"
  else
    log_warn "${LABEL} is not loaded"
    if [[ -f "${PLIST_PATH}" ]]; then
      log "plist present: ${PLIST_PATH}"
    else
      log "plist missing: ${PLIST_PATH}"
    fi
    exit 1
  fi
}

# launchd_logs
#   Tail stdout and stderr logs (requires STATE_DIR, STDOUT_LOG, STDERR_LOG)
launchd_logs() {
  if [[ -z "${STATE_DIR:-}" ]] || [[ -z "${STDOUT_LOG:-}" ]] || [[ -z "${STDERR_LOG:-}" ]]; then
    log_err "STATE_DIR, STDOUT_LOG, and STDERR_LOG must be set for launchd_logs"
    exit 1
  fi

  mkdir -p "${STATE_DIR}"
  touch "${STDOUT_LOG}" "${STDERR_LOG}"
  log "tailing logs (ctrl-c to exit)"
  tail -n 100 -f "${STDOUT_LOG}" "${STDERR_LOG}"
}

# launchd_stop
#   Stop service if loaded
launchd_stop() {
  if launchd_is_loaded; then
    launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
    log_ok "stopped ${LABEL}"
  else
    log_skip "${LABEL} is not loaded"
  fi
}

# launchd_start PLIST_PATH
#   Start service from plist file
launchd_start() {
  local plist="${1:-${PLIST_PATH}}"

  if [[ ! -f "${plist}" ]]; then
    log_err "plist not found: ${plist}; run install first"
    exit 1
  fi

  if ! launchd_is_loaded; then
    launchctl bootstrap "${DOMAIN}" "${plist}"
  fi

  launchctl enable "${DOMAIN}/${LABEL}"
  launchctl kickstart -k "${DOMAIN}/${LABEL}"
  log_ok "started ${LABEL}"
}

# launchd_restart
#   Restart service (stop then start)
launchd_restart() {
  launchd_stop
  launchd_start "$@"
}
