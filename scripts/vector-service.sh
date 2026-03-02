#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="vector-service"

if [[ "$(uname -s)" != "Darwin" ]]; then
  log_err "launchd management is only supported on macOS"
  exit 1
fi

LABEL="com.rentamac.vector"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${PLIST_DIR}/${LABEL}.plist"
VECTOR_BIN="$(command -v vector || true)"
CONFIG_PATH="${ROOT_DIR}/vector/.config/vector/vector.yaml"
STATE_DIR="${HOME}/.local/state/vector"
STDOUT_LOG="${STATE_DIR}/launchd.stdout.log"
STDERR_LOG="${STATE_DIR}/launchd.stderr.log"
DOMAIN="gui/${UID}"

usage() {
  cat <<'EOF'
Usage: vector-service.sh <command>

Commands:
  install     Write LaunchAgent plist and bootstrap service
  uninstall   Stop service and remove LaunchAgent plist
  start       Start service if installed
  stop        Stop service if running
  restart     Restart service
  status      Print launchd status for service
  logs        Tail Vector launchd stdout/stderr logs
EOF
}

require_vector() {
  if [[ -z "${VECTOR_BIN}" ]]; then
    log_err "vector binary not found on PATH"
    log "install: brew tap vectordotdev/brew && brew install vector"
    exit 1
  fi
}

require_config() {
  if [[ ! -f "${CONFIG_PATH}" ]]; then
    log_err "missing Vector config: ${CONFIG_PATH}"
    exit 1
  fi
}

write_plist() {
  mkdir -p "${PLIST_DIR}" "${STATE_DIR}" "${HOME}/logs/ai"

  cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${VECTOR_BIN}</string>
    <string>--config</string>
    <string>${CONFIG_PATH}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>${HOME}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${HOME}/.local/bin</string>
  </dict>
  <key>StandardOutPath</key>
  <string>${STDOUT_LOG}</string>
  <key>StandardErrorPath</key>
  <string>${STDERR_LOG}</string>
</dict>
</plist>
EOF
}

is_loaded() {
  launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1
}

do_install() {
  require_vector
  require_config

  if ! "${VECTOR_BIN}" validate "${CONFIG_PATH}" >/dev/null 2>&1; then
    log_err "Vector config validation failed: ${CONFIG_PATH}"
    exit 1
  fi

  write_plist

  if is_loaded; then
    launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
  fi

  launchctl bootstrap "${DOMAIN}" "${PLIST_PATH}"
  launchctl enable "${DOMAIN}/${LABEL}"
  launchctl kickstart -k "${DOMAIN}/${LABEL}"
  log_ok "installed and started ${LABEL}"
}

do_uninstall() {
  if is_loaded; then
    launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
  fi
  if [[ -f "${PLIST_PATH}" ]]; then
    rm -f "${PLIST_PATH}"
  fi
  log_ok "uninstalled ${LABEL}"
}

do_start() {
  if [[ ! -f "${PLIST_PATH}" ]]; then
    log_err "plist not found: ${PLIST_PATH}; run install first"
    exit 1
  fi
  if ! is_loaded; then
    launchctl bootstrap "${DOMAIN}" "${PLIST_PATH}"
  fi
  launchctl enable "${DOMAIN}/${LABEL}"
  launchctl kickstart -k "${DOMAIN}/${LABEL}"
  log_ok "started ${LABEL}"
}

do_stop() {
  if is_loaded; then
    launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
    log_ok "stopped ${LABEL}"
  else
    log_skip "${LABEL} is not loaded"
  fi
}

do_restart() {
  do_stop
  do_start
}

do_status() {
  if is_loaded; then
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

do_logs() {
  mkdir -p "${STATE_DIR}"
  touch "${STDOUT_LOG}" "${STDERR_LOG}"
  log "tailing logs (ctrl-c to exit)"
  tail -n 100 -f "${STDOUT_LOG}" "${STDERR_LOG}"
}

cmd="${1:-}"
case "${cmd}" in
  install) do_install ;;
  uninstall) do_uninstall ;;
  start) do_start ;;
  stop) do_stop ;;
  restart) do_restart ;;
  status) do_status ;;
  logs) do_logs ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    log_err "unknown command: ${cmd}"
    usage
    exit 1
    ;;
esac
