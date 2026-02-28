#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/raycast-scripts"
DEST_DIR="${HOME}/.config/raycast/scripts"

log() {
  if command -v gum >/dev/null 2>&1 && [[ -t 1 ]]; then
    gum style --foreground 212 "[raycast-scripts] $*"
  else
    printf '[raycast-scripts] %s\n' "$*"
  fi
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  log "Raycast script setup is macOS-only; skipping."
  exit 0
fi

if [[ ! -d "${SRC_DIR}" ]]; then
  log "No managed raycast-scripts directory found."
  exit 0
fi

mkdir -p "${DEST_DIR}"

for f in "${SRC_DIR}"/*.sh; do
  [[ -f "${f}" ]] || continue
  chmod +x "${f}"
  ln -sfn "${f}" "${DEST_DIR}/$(basename "${f}")"
  log "linked $(basename "${f}")"
done

log "Scripts linked to ${DEST_DIR}"
log "In Raycast: Extensions -> Script Commands -> add/import this directory if needed."
