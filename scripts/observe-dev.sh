#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="observe"

usage() {
  cat <<'EOF'
Usage: scripts/observe-dev.sh <mode>

Modes:
  summary        Print one-shot runtime/k8s/container summary
  k8s            Open k9s UI
  logs [pattern] Tail Kubernetes logs with stern (default pattern: .)
  docker         Live-refresh docker container list
  docker-events  Stream docker events
  docker-stats   Stream docker stats
EOF
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_err "missing command: $1"
    exit 1
  fi
}

summary() {
  printf '[observe] docker context: '
  docker context show 2>/dev/null || echo "unavailable"
  printf '[observe] docker server: '
  docker info --format '{{.ServerVersion}}' 2>/dev/null || echo "unavailable"
  printf '[observe] kube context: '
  kubectl config current-context 2>/dev/null || echo "unavailable"
  log "pods (all namespaces):"
  kubectl get pods -A 2>/dev/null | sed -n '1,25p' || echo "unavailable"
  log "containers:"
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || echo "unavailable"
}

live_docker() {
  while true; do
    clear
    date
    echo
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    sleep 2
  done
}

mode="${1:-summary}"
pattern="${2:-.}"

case "${mode}" in
  summary)
    need_cmd docker
    need_cmd kubectl
    summary
    ;;
  k8s)
    need_cmd k9s
    exec k9s
    ;;
  logs)
    need_cmd stern
    exec stern "${pattern}" -A
    ;;
  docker)
    need_cmd docker
    live_docker
    ;;
  docker-events)
    need_cmd docker
    exec docker events
    ;;
  docker-stats)
    need_cmd docker
    exec docker stats
    ;;
  *)
    usage
    exit 1
    ;;
esac
