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

if [[ ${#failed_optional[@]} -gt 0 ]]; then
  log_warn "optional tool installs failed: ${failed_optional[*]}"
fi
log_ok "dev tools setup complete"
