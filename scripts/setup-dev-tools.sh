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
DEVKIT_SRC="${HOME}/dev/devkit"
if [[ -d "${DEVKIT_SRC}" ]] && has_cmd go; then
  if (cd "${DEVKIT_SRC}" && go install ./cmd/devkit 2>/dev/null); then
    log_ok "devkit installed"
  else
    log_warn "devkit install failed; skipping"
  fi
else
  log_skip "devkit: source not found or go missing"
fi

if [[ ${#failed_optional[@]} -gt 0 ]]; then
  log_warn "optional tool installs failed: ${failed_optional[*]}"
fi
log_ok "dev tools setup complete"
