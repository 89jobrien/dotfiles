#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="rust-clean"

SCAN_DIR="${RUST_CLEAN_DIR:-${HOME}/dev}"
KEEP_DAYS="${RUST_CLEAN_DAYS:-14}"
DRY_RUN="${RUST_CLEAN_DRY_RUN:-0}"

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
  RUST_CLEAN_DRY_RUN=1
EOF
}

for arg in "$@"; do
  case "${arg}" in
    --dry-run) DRY_RUN=1 ;;
    --dir)     shift; SCAN_DIR="${1:-${SCAN_DIR}}" ;;
    --days)    shift; KEEP_DAYS="${1:-${KEEP_DAYS}}" ;;
    -h|--help) usage; exit 0 ;;
    *) log_err "unknown argument: ${arg}"; usage; exit 1 ;;
  esac
done

if ! command -v cargo-sweep >/dev/null 2>&1; then
  log_err "cargo-sweep not found; run: mise run dev-tools"
  exit 1
fi

if [[ ! -d "${SCAN_DIR}" ]]; then
  log_skip "scan dir not found: ${SCAN_DIR}"
  exit 0
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  log "dry-run: artifacts older than ${KEEP_DAYS} days under ${SCAN_DIR}"
  cargo sweep --time "${KEEP_DAYS}" --recursive --dry-run "${SCAN_DIR}"
else
  log "sweeping artifacts older than ${KEEP_DAYS} days under ${SCAN_DIR}..."
  cargo sweep --time "${KEEP_DAYS}" --recursive "${SCAN_DIR}"
  log_ok "rust artifact sweep complete"
fi
