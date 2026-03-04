#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="maestro"

maestro_dir() {
  if [[ -n "${DOT_MAESTRO_DIR:-}" ]]; then
    printf '%s\n' "${DOT_MAESTRO_DIR}"
    return
  fi
  if [[ -n "${PJ_MAESTRO_DIR:-}" ]]; then
    printf '%s\n' "${PJ_MAESTRO_DIR}"
    return
  fi
  printf '%s\n' "${HOME}/Documents/GitHub/maestro"
}

handoff_dir() {
  if [[ -n "${DOT_PRIVATE_CTX_DIR:-}" ]]; then
    printf '%s\n' "${DOT_PRIVATE_CTX_DIR}"
    return
  fi
  if [[ -n "${PJ_PRIVATE_CTX_DIR:-}" ]]; then
    printf '%s\n' "${PJ_PRIVATE_CTX_DIR}"
    return
  fi
  printf '%s\n' "${HOME}/.ctx/handoffs"
}

repo="$(maestro_dir)"
ctx_dir="$(handoff_dir)"

require_repo() {
  if [[ ! -d "${repo}" ]]; then
    log_err "repo not found: ${repo}"
    log "set DOT_MAESTRO_DIR to override"
    exit 1
  fi
}

cmd_where() {
  printf '%s\n' "${repo}"
}

cmd_doctor() {
  local status=0
  log "repo=${repo}"
  log "handoff_dir=${ctx_dir}"
  if [[ ! -d "${repo}" ]]; then
    log_err "repo missing (${repo})"
    status=1
  fi

  for marker in Makefile Cargo.toml Tiltfile maestro-cli maestro-api; do
    if [[ -e "${repo}/${marker}" ]]; then
      log_ok "marker ${marker}"
    else
      log_err "marker ${marker} missing"
      status=1
    fi
  done

  for c in make cargo docker kubectl k3d tilt; do
    if has_cmd "${c}"; then
      log_ok "${c} -> $(command -v "${c}")"
    else
      log_err "${c} missing"
      status=1
    fi
  done

  if [[ ${status} -ne 0 ]]; then
    log_err "FAIL"
    exit 1
  fi
  log_ok "PASS"
}

cmd_up() {
  local quick="${1:-0}"
  local api_run="${2:-0}"
  require_repo
  log "running make dev-setup"
  (cd "${repo}" && make dev-setup)
  if [[ "${quick}" != "1" ]]; then
    log "running make ci"
    (cd "${repo}" && make ci)
  fi
  if [[ "${api_run}" == "1" ]]; then
    log "running make api-run"
    (cd "${repo}" && make api-run)
  fi
}

cmd_handoff() {
  require_repo
  mkdir -p "${ctx_dir}"
  local ts branch status_count path
  ts="$(date +%s)"
  branch="$(cd "${repo}" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  status_count="$(cd "${repo}" && git status --short 2>/dev/null | wc -l | tr -d ' ')"
  path="${ctx_dir}/maestro__HANDOFF-${ts}.local.md"
  cat > "${path}" <<EOF
# maestro__HANDOFF

## Snapshot
- Timestamp: ${ts}
- Repo: \`${repo}\`
- Branch: \`${branch}\`
- Status: \`${status_count}\` changed paths locally

## Known Entry Points
- \`make dev-setup\`
- \`make ci\`
- \`make api-run\`
- \`make cli-test-k8s-setup && make cli-test-k8s\`
- \`make tilt-up\`

## Dotfiles Commands
- \`mise run maestro-doctor\`
- \`mise run maestro-up\`
- \`mise run maestro-up-quick\`
- \`mise run maestro-up-api\`
- \`mise run maestro-handoff\`

## Notes
- Stored in private ctx dir: \`${ctx_dir}\`
- Repo-specific secrets/context should remain outside work repo.
EOF
  log_ok "wrote handoff: ${path}"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  where               Print resolved maestro directory
  doctor              Validate maestro repo markers and required commands
  up [--quick] [--api-run]
                      Run make dev-setup, optionally skip ci or run api-run
  handoff             Write maestro handoff in ~/.ctx/handoffs
EOF
}

command="${1:-help}"
shift || true

case "${command}" in
  where)
    cmd_where
    ;;
  doctor)
    cmd_doctor
    ;;
  up)
    quick=0
    api_run=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --quick) quick=1 ;;
        --api-run) api_run=1 ;;
        *)
          echo "unknown option: $1"
          usage
          exit 1
          ;;
      esac
      shift
    done
    cmd_up "${quick}" "${api_run}"
    ;;
  handoff)
    cmd_handoff
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "unknown command: ${command}"
    usage
    exit 1
    ;;
esac
