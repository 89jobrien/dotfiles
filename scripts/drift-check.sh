#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="drift"

STOW_LIST_FILE="${ROOT_DIR}/config/stow-packages.txt"

status=0

log "repo=${ROOT_DIR}"

if ! git -C "${ROOT_DIR}" diff --quiet || ! git -C "${ROOT_DIR}" diff --cached --quiet; then
  log_warn "dotfiles repo has uncommitted changes"
  status=1
fi

if has_cmd stow && [[ -f "${STOW_LIST_FILE}" ]]; then
  while IFS= read -r pkg; do
    [[ -z "${pkg}" || "${pkg}" =~ ^[[:space:]]*# ]] && continue
    if stow -d "${ROOT_DIR}" -t "${HOME}" -n "${pkg}" 2>&1 | grep -Eq 'would cause conflicts|cannot stow|existing target is not owned by stow|ERROR'; then
      log_warn "stow conflict for package: ${pkg}"
      status=1
    fi
  done < "${STOW_LIST_FILE}"
fi

if [[ $status -ne 0 ]]; then
  log_err "FAIL"
  exit 1
fi

log_ok "PASS"
