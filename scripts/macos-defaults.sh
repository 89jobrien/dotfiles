#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[macos-defaults] %s\n' "$*"
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  log "Skipping: non-macOS host."
  exit 0
fi

if [[ ! -d "/Applications/Alacritty.app" ]]; then
  if command -v alacritty >/dev/null 2>&1; then
    log "Alacritty is installed from source/binary (no .app bundle)."
    log "Skipping duti app-bundle handler setup."
  else
    log "Alacritty not found. Run bootstrap first."
  fi
  exit 0
fi

if ! command -v duti >/dev/null 2>&1; then
  log "duti not installed. Cannot set file handlers."
  exit 0
fi

# Best-effort default terminal handler setup.
for uti in public.unix-executable public.shell-script public.zsh-script public.bash-script; do
  duti -s org.alacritty "${uti}" all || true
done

log "Configured Alacritty handler defaults."
