#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="dev-tools"

failed_optional=()

# JS workflow baseline — BAML CLI for AI boundary definitions.
if has_cmd bun; then
  ensure_cmd "baml-cli" "bun add -g @boundaryml/baml" "failed_optional" || true
elif has_cmd npm; then
  log_warn "bun missing; using npm fallback for BAML CLI"
  ensure_cmd "baml-cli" "npm install -g @boundaryml/baml" "failed_optional" || true
else
  log_skip "neither bun nor npm found; skipping baml-cli"
fi

# devkit — AI-powered dev workflow toolkit
# Source path is configurable via DEVKIT_SRC env var; defaults to ~/dev/devkit
DEVKIT_SRC="${DEVKIT_SRC:-${HOME}/dev/devkit}"
if ! has_cmd go; then
  log_skip "devkit: go not found (install go via mise)"
elif [[ ! -d "${DEVKIT_SRC}" ]]; then
  log_skip "devkit: source not found at ${DEVKIT_SRC} (set DEVKIT_SRC or clone 89jobrien/devkit)"
else
  _devkit_log="$(mktemp)"
  trap 'rm -f "${_devkit_log}"' EXIT
  if (cd "${DEVKIT_SRC}" && go install ./cmd/devkit 2>"${_devkit_log}"); then
    log_ok "devkit installed"
  else
    log_warn "devkit install failed:"
    cat "${_devkit_log}" >&2
  fi
  rm -f "${_devkit_log}"
  trap - EXIT
fi

if [[ ${#failed_optional[@]} -gt 0 ]]; then
  log_warn "optional tool installs failed: ${failed_optional[*]}"
fi
log_ok "dev tools setup complete"
