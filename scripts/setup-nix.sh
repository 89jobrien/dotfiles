#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="nix"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

resolve_system() {
  local arch kernel
  arch="$(uname -m)"
  kernel="$(uname -s)"

  case "${kernel}" in
    Darwin) kernel="darwin" ;;
    Linux)  kernel="linux"  ;;
    *)
      log_err "unsupported OS: ${kernel}"
      return 1
      ;;
  esac

  # Normalise arm64 → aarch64
  case "${arch}" in
    arm64) arch="aarch64" ;;
  esac

  printf '%s-%s' "${arch}" "${kernel}"
}

# ---------------------------------------------------------------------------
# Install Nix (Determinate Systems installer)
# ---------------------------------------------------------------------------

install_nix() {
  if has_cmd nix; then
    log_skip "nix already installed ($(nix --version))"
    return 0
  fi

  log "installing Nix via Determinate Systems installer..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm

  # Source nix-daemon so nix is available in this shell session
  if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    # shellcheck disable=SC1091
    source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
  fi

  if ! has_cmd nix; then
    log_err "nix not found on PATH after install"
    return 1
  fi

  log_ok "nix installed ($(nix --version))"
}

# ---------------------------------------------------------------------------
# Install / upgrade flake packages
# ---------------------------------------------------------------------------

install_packages() {
  local system
  system="$(resolve_system)"

  local flake_ref="path:${ROOT_DIR}"
  local attr="${flake_ref}#packages.${system}.default"

  # Profile entries are named; ours is called "dotfiles" (derived from flake name).
  # Strip ANSI escape codes before matching (nix profile list uses bold formatting).
  if nix profile list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "dotfiles"; then
    log "upgrading nix profile packages..."
    nix profile upgrade dotfiles
    log_ok "nix profile upgraded"
  else
    log "installing nix profile packages..."
    nix profile install "${attr}"
    log_ok "nix profile installed"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  install_nix
  install_packages
}

main
