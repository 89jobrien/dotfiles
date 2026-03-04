#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
source "${ROOT_DIR}/scripts/lib/dryrun.sh"
TAG="rust-clean"

SCAN_DIR="${RUST_CLEAN_DIR:-${HOME}/dev}"
KEEP_DAYS="${RUST_CLEAN_DAYS:-14}"

usage() {
  cat <<'EOF'
Usage: rust-clean.sh [--dry-run] [--dir <path>] [--days <n>]

Sweeps Rust build artifacts older than KEEP_DAYS days from all projects
under SCAN_DIR using cargo-sweep.

Options:
  --dry-run     Preview what would be removed without deleting
  --dir <path>  Directory to scan (default: ~/dev)
  --days <n>    Remove artifacts older than N days (default: 14)

Environment overrides:
  RUST_CLEAN_DIR  (default: ~/dev)
  RUST_CLEAN_DAYS (default: 14)
  DRY_RUN=1
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) set_dryrun_mode 1 ;;
    --dir)     shift; SCAN_DIR="${1:?--dir requires a path}" ;;
    --days)    shift; KEEP_DAYS="${1:?--days requires a number}" ;;
    -h|--help) usage; exit 0 ;;
    *) log_err "unknown argument: $1"; usage; exit 1 ;;
  esac
  shift
done

require_cmd cargo-sweep "mise run dev-tools"

if [[ ! -d "${SCAN_DIR}" ]]; then
  log_skip "scan dir not found: ${SCAN_DIR}"
  exit 0
fi

if is_dryrun; then
  log "dry-run: artifacts older than ${KEEP_DAYS} days under ${SCAN_DIR}"
  cargo sweep --time "${KEEP_DAYS}" --recursive --dry-run "${SCAN_DIR}"
else
  log "sweeping artifacts older than ${KEEP_DAYS} days under ${SCAN_DIR}..."
  cargo sweep --time "${KEEP_DAYS}" --recursive "${SCAN_DIR}"
  log_ok "rust artifact sweep complete"
fi
