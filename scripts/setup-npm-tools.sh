#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"

TAG="npm-tools"

# Install npm-based tools via regular Homebrew (not zerobrew) to avoid symlink conflicts
if ! command -v brew &> /dev/null; then
  log_skip "Homebrew not found"
  exit 0
fi

log "installing npm-based tools via brew..."
brew install --quiet opencode

log_ok "npm-based tools installed"
