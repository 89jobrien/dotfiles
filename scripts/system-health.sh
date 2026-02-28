#!/usr/bin/env bash
set -euo pipefail

mode="${1:-summary}"

log() {
  if command -v gum >/dev/null 2>&1 && [[ -t 1 ]]; then
    gum style --foreground 212 "[health] $*"
  else
    printf '[health] %s\n' "$*"
  fi
}

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
  if command -v duf >/dev/null 2>&1; then
    duf
  else
    df -h
  fi

  echo
  log "largest directories (cwd)"
  if command -v dust >/dev/null 2>&1; then
    dust -r -d 2 .
  else
    du -h -d 2 . 2>/dev/null | sort -h | tail -n 20
  fi

  echo
  log "top processes"
  if command -v procs >/dev/null 2>&1; then
    procs --sortd cpu | head -n 25
  else
    ps aux | head -n 25
  fi
}

live() {
  log "live monitor"
  if command -v btm >/dev/null 2>&1; then
    exec btm
  elif command -v btop >/dev/null 2>&1; then
    exec btop
  else
    log "install one of: bottom (btm) or btop"
    exec top
  fi
}

procs_view() {
  if command -v procs >/dev/null 2>&1; then
    exec procs --sortd cpu
  fi
  exec ps aux
}

disk_view() {
  if command -v duf >/dev/null 2>&1; then
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
