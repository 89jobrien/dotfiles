#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="oh-my-zsh"

main() {
  if ! command -v zsh >/dev/null 2>&1; then
    log_skip "zsh not found"
    return 0
  fi

  if [[ -d "${HOME}/.oh-my-zsh" ]]; then
    log_skip "already installed"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log_err "curl not found; cannot install Oh My Zsh automatically"
    return 1
  fi

  log "installing Oh My Zsh (unattended, keeping existing .zshrc)..."
  local install_script=""
  install_script="$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh 2>/dev/null || true)"
  if [[ -z "${install_script}" ]]; then
    log_warn "primary installer URL unavailable; trying mirror https://install.ohmyz.sh/"
    install_script="$(curl -fsSL https://install.ohmyz.sh/ 2>/dev/null || true)"
  fi
  if [[ -z "${install_script}" ]]; then
    log_err "failed to download Oh My Zsh installer script"
    return 1
  fi

  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "${install_script}" "" --unattended --keep-zshrc

  if [[ -d "${HOME}/.oh-my-zsh" ]]; then
    log_ok "Oh My Zsh installed"
  else
    log_err "Oh My Zsh install did not complete"
    return 1
  fi
}

main "$@"
