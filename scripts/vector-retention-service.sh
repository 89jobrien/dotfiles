#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/launchd.sh"
TAG="vector-retention-service"

if [[ "$(uname -s)" != "Darwin" ]]; then
  log_err "launchd management is only supported on macOS"
  exit 1
fi

LABEL="com.rentamac.vector-retention"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${PLIST_DIR}/${LABEL}.plist"
SCRIPT_PATH="${ROOT_DIR}/scripts/claude-log-retention.sh"
STATE_DIR="${HOME}/.local/state/vector"
STDOUT_LOG="${STATE_DIR}/retention.stdout.log"
STDERR_LOG="${STATE_DIR}/retention.stderr.log"
DOMAIN="gui/${UID}"

SCHEDULE_HOUR="${VECTOR_RETENTION_HOUR:-3}"
SCHEDULE_MINUTE="${VECTOR_RETENTION_MINUTE:-15}"

usage() {
  cat <<'EOF'
Usage: vector-retention-service.sh <command>

Commands:
  install     Write LaunchAgent plist and bootstrap scheduled service
  uninstall   Remove scheduled service and plist
  status      Print launchd status for scheduler
  run-now     Trigger one immediate retention run
  logs        Tail retention stdout/stderr logs

Environment overrides:
  VECTOR_RETENTION_HOUR (default: 3)
  VECTOR_RETENTION_MINUTE (default: 15)
EOF
}

write_plist() {
  mkdir -p "${PLIST_DIR}" "${STATE_DIR}"

  cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${SCRIPT_PATH}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${HOME}</string>
  <key>RunAtLoad</key>
  <false/>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>${SCHEDULE_HOUR}</integer>
    <key>Minute</key>
    <integer>${SCHEDULE_MINUTE}</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>${STDOUT_LOG}</string>
  <key>StandardErrorPath</key>
  <string>${STDERR_LOG}</string>
</dict>
</plist>
EOF
}

do_install() {
  if [[ ! -x "${SCRIPT_PATH}" ]]; then
    log_err "retention script missing or not executable: ${SCRIPT_PATH}"
    exit 1
  fi

  write_plist

  if launchd_is_loaded; then
    launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
  fi

  launchctl bootstrap "${DOMAIN}" "${PLIST_PATH}"
  launchctl enable "${DOMAIN}/${LABEL}"
  log_ok "installed schedule ${SCHEDULE_HOUR}:$(printf '%02d' "${SCHEDULE_MINUTE}") for ${LABEL}"
}

do_uninstall() {
  launchd_uninstall
}

do_status() {
  launchd_status
}

do_run_now() {
  if [[ ! -f "${PLIST_PATH}" ]]; then
    log_err "plist not found: ${PLIST_PATH}; run install first"
    exit 1
  fi
  if ! launchd_is_loaded; then
    launchctl bootstrap "${DOMAIN}" "${PLIST_PATH}"
  fi
  launchctl kickstart -k "${DOMAIN}/${LABEL}"
  log_ok "triggered immediate run"
}

do_logs() {
  launchd_logs
}

cmd="${1:-}"
case "${cmd}" in
  install) do_install ;;
  uninstall) do_uninstall ;;
  status) do_status ;;
  run-now) do_run_now ;;
  logs) do_logs ;;
  -h|--help|help|"") usage ;;
  *)
    log_err "unknown command: ${cmd}"
    usage
    exit 1
    ;;
esac
