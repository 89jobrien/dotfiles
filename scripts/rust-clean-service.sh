#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/launchd.sh"
TAG="rust-clean-service"

if [[ "$(uname -s)" != "Darwin" ]]; then
  log_err "launchd management is only supported on macOS"
  exit 1
fi

LABEL="com.rentamac.rust-clean"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${PLIST_DIR}/${LABEL}.plist"
SCRIPT_PATH="${ROOT_DIR}/scripts/rust-clean.sh"
STATE_DIR="${HOME}/.local/state/rust-clean"
STDOUT_LOG="${STATE_DIR}/rust-clean.stdout.log"
STDERR_LOG="${STATE_DIR}/rust-clean.stderr.log"
DOMAIN="gui/${UID}"

SCHEDULE_WEEKDAY="${RUST_CLEAN_WEEKDAY:-0}"   # 0 = Sunday
SCHEDULE_HOUR="${RUST_CLEAN_HOUR:-3}"
SCHEDULE_MINUTE="${RUST_CLEAN_MINUTE:-30}"
SCAN_DIR="${RUST_CLEAN_DIR:-${HOME}/dev}"
KEEP_DAYS="${RUST_CLEAN_DAYS:-14}"

usage() {
  cat <<'EOF'
Usage: rust-clean-service.sh <command>

Commands:
  install     Write LaunchAgent plist and bootstrap weekly service
  uninstall   Remove scheduled service and plist
  status      Print launchd status
  run-now     Trigger one immediate cleanup run
  logs        Tail service stdout/stderr logs

Environment overrides:
  RUST_CLEAN_DIR      directory to scan (default: ~/dev)
  RUST_CLEAN_DAYS     artifact age threshold in days (default: 14)
  RUST_CLEAN_WEEKDAY  day of week to run, 0=Sun (default: 0)
  RUST_CLEAN_HOUR     hour to run (default: 3)
  RUST_CLEAN_MINUTE   minute to run (default: 30)
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
    <string>/bin/bash</string>
    <string>${SCRIPT_PATH}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>RUST_CLEAN_DIR</key>
    <string>${SCAN_DIR}</string>
    <key>RUST_CLEAN_DAYS</key>
    <string>${KEEP_DAYS}</string>
    <key>HOME</key>
    <string>${HOME}</string>
    <key>PATH</key>
    <string>${HOME}/.cargo/bin:${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>WorkingDirectory</key>
  <string>${HOME}</string>
  <key>RunAtLoad</key>
  <false/>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key>
    <integer>${SCHEDULE_WEEKDAY}</integer>
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
  if [[ ! -f "${SCRIPT_PATH}" ]]; then
    log_err "clean script missing: ${SCRIPT_PATH}"
    exit 1
  fi
  chmod +x "${SCRIPT_PATH}"

  write_plist

  if launchd_is_loaded; then
    launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
  fi

  launchctl bootstrap "${DOMAIN}" "${PLIST_PATH}"
  launchctl enable "${DOMAIN}/${LABEL}"
  local day_names=(Sun Mon Tue Wed Thu Fri Sat)
  log_ok "installed: every ${day_names[${SCHEDULE_WEEKDAY}]} at ${SCHEDULE_HOUR}:$(printf '%02d' "${SCHEDULE_MINUTE}") — scanning ${SCAN_DIR} (>${KEEP_DAYS}d old)"
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
  install)   do_install ;;
  uninstall) do_uninstall ;;
  status)    do_status ;;
  run-now)   do_run_now ;;
  logs)      do_logs ;;
  -h|--help|help|"") usage ;;
  *)
    log_err "unknown command: ${cmd}"
    usage
    exit 1
    ;;
esac
