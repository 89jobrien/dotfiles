#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="nushell"

main() {
  if ! has_cmd nu; then
    log_skip "nushell not found"
    return 0
  fi

  NU_PATH="$(command -v nu)"

  # Add nu to /etc/shells if not already present
  if ! grep -qF "${NU_PATH}" /etc/shells; then
    log "adding ${NU_PATH} to /etc/shells..."
    echo "${NU_PATH}" | sudo tee -a /etc/shells > /dev/null
    log_ok "added to /etc/shells"
  else
    log_skip "${NU_PATH} already in /etc/shells"
  fi

  # Set nu as the default login shell
  local current_shell
  current_shell="$(getent passwd "${USER}" | cut -d: -f7)"
  if [[ "${current_shell}" == "${NU_PATH}" ]]; then
    log_skip "nushell is already the default shell"
    return 0
  fi

  log "setting default shell to ${NU_PATH}..."
  chsh -s "${NU_PATH}" "${USER}"
  log_ok "default shell set to nushell (takes effect on next login)"
}

main "$@"
