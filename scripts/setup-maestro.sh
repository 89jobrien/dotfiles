#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="maestro"

MAESTRO_DIR="${DOT_MAESTRO_DIR:-${PJ_MAESTRO_DIR:-${HOME}/Documents/GitHub/maestro}}"

validate_repo() {
  if [[ ! -d "${MAESTRO_DIR}" ]]; then
    log_skip "repo not found at ${MAESTRO_DIR}"
    return 0
  fi
  log "repo exists at ${MAESTRO_DIR}"
}

check_dev_deps() {
  if [[ ! -f "${MAESTRO_DIR}/Makefile" && ! -f "${MAESTRO_DIR}/Justfile" ]]; then
    log_skip "no Makefile or Justfile found in ${MAESTRO_DIR}"
    return 0
  fi
  log "dev files present in ${MAESTRO_DIR}"
}

run_setup_script() {
  local setup_script="${MAESTRO_DIR}/scripts/setup.sh"
  if [[ -f "${setup_script}" ]]; then
    log "running ${setup_script}..."
    bash "${setup_script}"
    return $?
  fi
  log_skip "no setup script at ${setup_script}"
  return 0
}

main() {
  validate_repo
  check_dev_deps
  if [[ -d "${MAESTRO_DIR}" ]]; then
    run_setup_script
  fi
}

main "$@"
