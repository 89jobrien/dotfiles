#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="zerobrew"

if has_cmd zb; then
  log_skip "zb already installed at $(find_cmd zb)"
  exit 0
fi

if ! has_cmd curl; then
  log_err "curl is required to install zerobrew"
  exit 1
fi

if [[ ! -t 0 ]]; then
  log_skip "non-interactive mode; skipping zerobrew install"
  log "run manually in a terminal (installer may prompt for your password):"
  log "  curl -fsSL https://zerobrew.rs/install | bash"
  exit 0
fi

log "installing zerobrew..."
log "the installer may prompt for your macOS password"
tmp_installer="$(mktemp "${TMPDIR:-/tmp}/zerobrew-install.XXXXXX.sh")"
cleanup() {
  rm -f "${tmp_installer}"
}
trap cleanup EXIT

curl --proto '=https' --tlsv1.2 -fsSL "https://zerobrew.rs/install" -o "${tmp_installer}"
if ! grep -Eiq 'zerobrew|zero ?brew' "${tmp_installer}"; then
  log_err "downloaded installer did not look like zerobrew script; aborting"
  exit 1
fi

bash "${tmp_installer}"

if has_cmd zb; then
  log_ok "installed zb at $(find_cmd zb)"
  exit 0
fi

if [[ -x "${HOME}/.zerobrew/bin/zb" ]]; then
  log_ok "installed zb at ${HOME}/.zerobrew/bin/zb"
  exit 0
fi

if [[ -x "${HOME}/.local/bin/zb" ]]; then
  log_ok "installed zb at ${HOME}/.local/bin/zb"
  exit 0
fi

log_warn "install completed but zb is not on PATH yet"
