#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
source "${ROOT_DIR}/scripts/lib/dryrun.sh"
TAG="maestro"

if [[ "${1:-}" == "--dry-run" ]]; then
  set_dryrun_mode 1
fi

MAESTRO_DIR="${DOT_MAESTRO_DIR:-${PJ_MAESTRO_DIR:-${HOME}/Documents/GitHub/maestro}}"
MAESTRO_REPO="${DOT_MAESTRO_REPO:-${PJ_MAESTRO_REPO:-}}"
MAESTRO_MODE="${DOT_MAESTRO_MODE:-quick}" # quick|full|api|none

clone_or_update_repo() {
  if [[ -d "${MAESTRO_DIR}/.git" ]]; then
    log "repo exists at ${MAESTRO_DIR}; updating..."
    dryrun_exec git -C "${MAESTRO_DIR}" pull --ff-only || {
      log_warn "git pull failed; continuing with existing checkout"
      return 0
    }
    return 0
  fi

  if [[ -z "${MAESTRO_REPO}" ]]; then
    log_skip "DOT_MAESTRO_REPO not set and repo missing at ${MAESTRO_DIR}"
    log "set DOT_MAESTRO_REPO (e.g. org/repo or git URL) to enable auto-clone"
    return 0
  fi

  log "cloning ${MAESTRO_REPO} into ${MAESTRO_DIR}..."
  mkdir -p "$(dirname "${MAESTRO_DIR}")"
  if has_cmd gh && gh auth status -h github.com >/dev/null 2>&1; then
    if [[ "${MAESTRO_REPO}" == *"/"* && "${MAESTRO_REPO}" != http* && "${MAESTRO_REPO}" != git@* ]]; then
      dryrun_exec gh repo clone "${MAESTRO_REPO}" "${MAESTRO_DIR}" -- --depth 1
      return 0
    fi
  fi
  dryrun_exec git clone "${MAESTRO_REPO}" "${MAESTRO_DIR}" --depth 1
}

run_maestro_setup() {
  if [[ "${MAESTRO_MODE}" == "none" ]]; then
    log_skip "DOT_MAESTRO_MODE=none"
    return 0
  fi

  if [[ ! -f "${MAESTRO_DIR}/Makefile" ]]; then
    log_skip "Makefile not found in ${MAESTRO_DIR}"
    return 0
  fi

  log "running Maestro setup mode='${MAESTRO_MODE}'..."
  case "${MAESTRO_MODE}" in
    quick)
      dryrun_exec make -C "${MAESTRO_DIR}" dev-setup
      ;;
    full)
      dryrun_exec make -C "${MAESTRO_DIR}" dev-setup
      dryrun_exec make -C "${MAESTRO_DIR}" ci
      ;;
    api)
      dryrun_exec make -C "${MAESTRO_DIR}" dev-setup
      dryrun_exec make -C "${MAESTRO_DIR}" ci
      dryrun_exec make -C "${MAESTRO_DIR}" api-run
      ;;
    *)
      log_warn "invalid DOT_MAESTRO_MODE='${MAESTRO_MODE}' (expected quick|full|api|none)"
      ;;
  esac
}

main() {
  clone_or_update_repo
  if [[ -d "${MAESTRO_DIR}" ]]; then
    run_maestro_setup
  fi
}

main "$@"
