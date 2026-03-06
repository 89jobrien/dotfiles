#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"

TAG="hooks"

HOOKS_REPO="${HOME}/dev/hooks"

if [[ ! -d "${HOOKS_REPO}" ]]; then
  log_skip "hooks repo not found at ${HOOKS_REPO}; skipping"
  exit 0
fi

log "building hook binaries..."
make -C "${HOOKS_REPO}" install

log "generating ~/.claude/hooks/hooks.json..."
cd "${HOOKS_REPO}" && make config

log_ok "hooks installed — restart Claude Code to apply"
