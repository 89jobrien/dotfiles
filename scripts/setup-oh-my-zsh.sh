#!/usr/bin/env bash
set -euo pipefail

log() {
  if command -v gum >/dev/null 2>&1 && [[ -t 1 ]]; then
    gum style --foreground 212 "[oh-my-zsh] $*"
  else
    printf '[oh-my-zsh] %s\n' "$*"
  fi
}

main() {
  if ! command -v zsh >/dev/null 2>&1; then
    log "zsh not found; skipping Oh My Zsh install."
    return 0
  fi

  if [[ -d "${HOME}/.oh-my-zsh" ]]; then
    log "Oh My Zsh already installed."
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log "curl not found; cannot install Oh My Zsh automatically."
    return 1
  fi

  log "Installing Oh My Zsh (unattended, keeping existing .zshrc)..."
  local install_script=""
  install_script="$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh 2>/dev/null || true)"
  if [[ -z "${install_script}" ]]; then
    log "Primary installer URL unavailable; trying mirror https://install.ohmyz.sh/"
    install_script="$(curl -fsSL https://install.ohmyz.sh/ 2>/dev/null || true)"
  fi
  if [[ -z "${install_script}" ]]; then
    log "Failed to download Oh My Zsh installer script."
    return 1
  fi

  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "${install_script}" "" --unattended --keep-zshrc

  if [[ -d "${HOME}/.oh-my-zsh" ]]; then
    log "Oh My Zsh installed."
  else
    log "Oh My Zsh install did not complete."
    return 1
  fi
}

main "$@"
