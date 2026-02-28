#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[zerobrew] %s\n' "$*"
}

if command -v zb >/dev/null 2>&1; then
  log "zb already installed at $(command -v zb)"
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  log "curl is required to install zerobrew."
  exit 1
fi

if [[ ! -t 0 ]]; then
  log "Skipping zerobrew install in non-interactive mode."
  log "Run manually in a terminal (installer may prompt for your password):"
  log "  curl -fsSL https://zerobrew.rs/install | bash"
  exit 0
fi

log "Installing zerobrew..."
log "The installer may prompt for your macOS password."
curl -fsSL https://zerobrew.rs/install | bash

if command -v zb >/dev/null 2>&1; then
  log "Installed zb at $(command -v zb)"
  exit 0
fi

if [[ -x "${HOME}/.zerobrew/bin/zb" ]]; then
  log "Installed zb at ${HOME}/.zerobrew/bin/zb"
  exit 0
fi

if [[ -x "${HOME}/.local/bin/zb" ]]; then
  log "Installed zb at ${HOME}/.local/bin/zb"
  exit 0
fi

log "Install completed but zb is not on PATH yet."
