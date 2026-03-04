#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="health"

mode="${1:-summary}"

summary() {
  log "host summary"
  printf 'time: %s\n' "$(date)"
  printf 'uptime: %s\n' "$(uptime | sed 's/^ *//')"
  printf 'kernel: %s\n' "$(uname -srmo 2>/dev/null || uname -a)"

  if [[ "$(uname -s)" == "Darwin" ]]; then
    # top provides a stable human-readable memory summary on macOS.
    mem_line="$(top -l 1 -n 0 2>/dev/null | awk -F': ' '/PhysMem:/ {print $2; exit}' || true)"
    if [[ -n "${mem_line}" ]]; then
      printf 'memory: %s\n' "${mem_line}"
    else
      printf 'memory: unavailable (restricted environment)\n'
    fi
  fi

  echo
  log "disk usage"
  if has_cmd duf; then
    duf
  else
    df -h
  fi

  echo
  log "largest directories (cwd)"
  if has_cmd dust; then
    dust -r -d 2 .
  else
    du -h -d 2 . 2>/dev/null | sort -h | tail -n 20
  fi

  echo
  log "top processes"
  if has_cmd procs; then
    procs --sortd cpu | head -n 25
  else
    ps aux | head -n 25
  fi
}

live() {
  log "live monitor"
  if has_cmd btm; then
    exec btm
  elif has_cmd btop; then
    exec btop
  else
    log_warn "install one of: bottom (btm) or btop"
    exec top
  fi
}

procs_view() {
  if has_cmd procs; then
    exec procs --sortd cpu
  fi
  exec ps aux
}

disk_view() {
  if has_cmd duf; then
    exec duf
  fi
  exec df -h
}

case "${mode}" in
  summary) summary ;;
  live) live ;;
  procs) procs_view ;;
  disk) disk_view ;;
  *)
    cat <<'EOF'
Usage: scripts/system-health.sh <mode>

Modes:
  summary   Print one-shot host/resource summary
  live      Open interactive monitor (btm, btop, or top)
  procs     Show process list (procs or ps)
  disk      Show disk usage (duf or df)
EOF
    exit 1
    ;;
esac
