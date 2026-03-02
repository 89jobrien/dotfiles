#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="compose"

compose_cmd=()

init_compose_cmd() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    compose_cmd=(docker compose)
    return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    compose_cmd=(docker-compose)
    return 0
  fi
  log_err "docker compose is not available"
  exit 1
}

run_compose() {
  "${compose_cmd[@]}" -f "${ROOT_DIR}/compose.yaml" "$@"
}

up() {
  log "starting compose stack"
  run_compose up -d
  log_ok "compose stack is up"
}

down() {
  log "stopping compose stack"
  run_compose down
  log_ok "compose stack is down"
}

status() {
  log "compose status"
  run_compose ps
}

logs() {
  log "streaming compose logs (ctrl-c to stop)"
  run_compose logs -f --tail=100
}

case "${1:-status}" in
  up) init_compose_cmd; up ;;
  down) init_compose_cmd; down ;;
  status) init_compose_cmd; status ;;
  logs) init_compose_cmd; logs ;;
  *)
    cat <<'EOF'
Usage: scripts/compose-dev.sh <command>

Commands:
  up      Build and start compose services in detached mode
  down    Stop and remove compose services
  status  Show service status
  logs    Follow service logs
EOF
    exit 1
    ;;
esac
