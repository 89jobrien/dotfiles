#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[alacritty-source] %s\n' "$*"
}

if command -v alacritty >/dev/null 2>&1; then
  log "Alacritty already installed at $(command -v alacritty)"
  exit 0
fi

if ! command -v cargo >/dev/null 2>&1; then
  log "cargo is required to build Alacritty from source."
  exit 1
fi

if command -v mise >/dev/null 2>&1; then
  log "Installing Alacritty from source via cargo (mise exec)..."
  mise exec -- cargo install --locked alacritty
else
  log "Installing Alacritty from source via cargo..."
  cargo install --locked alacritty
fi

log "Installed Alacritty: $(command -v alacritty)"
