#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
source "${ROOT_DIR}/scripts/lib/launchd.sh"
TAG="vector-service"

if [[ "$(uname -s)" != "Darwin" ]]; then
  log_err "launchd management is only supported on macOS"
  exit 1
fi

LABEL="com.rentamac.vector"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${PLIST_DIR}/${LABEL}.plist"
VECTOR_BIN=""
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
  require_cmd vector "brew tap vectordotdev/brew && brew install vector"
  VECTOR_BIN="$(find_cmd vector)"
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
  <key>SoftResourceLimits</key>
  <dict>
    <key>NumberOfFiles</key>
    <integer>4096</integer>
  </dict>
  <key>HardResourceLimits</key>
  <dict>
    <key>NumberOfFiles</key>
    <integer>4096</integer>
  </dict>
</dict>
</plist>
EOF
}

do_install() {
  require_vector
  require_config

  if ! "${VECTOR_BIN}" validate "${CONFIG_PATH}" >/dev/null 2>&1; then
    log_err "Vector config validation failed: ${CONFIG_PATH}"
    exit 1
  fi

  write_plist

  if launchd_is_loaded; then
    launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
  fi

  launchctl bootstrap "${DOMAIN}" "${PLIST_PATH}"
  launchctl enable "${DOMAIN}/${LABEL}"
  launchctl kickstart -k "${DOMAIN}/${LABEL}"
  log_ok "installed and started ${LABEL}"
}

do_uninstall() {
  launchd_uninstall
}

do_start() {
  launchd_start
}

do_stop() {
  launchd_stop
}

do_restart() {
  # shellcheck disable=SC2119  # launchd_restart takes no args; $@ intentionally not passed
  launchd_restart
}

do_status() {
  launchd_status
}

do_logs() {
  launchd_logs
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
