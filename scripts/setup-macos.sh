#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="macos"

if [[ "$(uname -s)" != "Darwin" ]]; then
  log_skip "non-macOS host"
  exit 0
fi

set_file_handlers() {
  if [[ ! -d "/Applications/Alacritty.app" ]]; then
    if has_cmd alacritty; then
      log_skip "Alacritty installed from source (no .app bundle); skipping duti setup"
    else
      log_skip "Alacritty not found; skipping handler setup"
    fi
    return 0
  fi

  if ! has_cmd duti; then
    log_skip "duti not installed; cannot set file handlers"
    return 0
  fi

  for uti in public.unix-executable public.shell-script public.zsh-script public.bash-script; do
    duti -s org.alacritty "${uti}" all || true
  done

  log_ok "configured Alacritty file handlers"
}

link_raycast_scripts() {
  local src_dir="${ROOT_DIR}/raycast-scripts"
  local dest_dir="${HOME}/.config/raycast/scripts"

  if [[ ! -d "${src_dir}" ]]; then
    log_skip "no managed raycast-scripts directory found"
    return 0
  fi

  mkdir -p "${dest_dir}"

  local count=0
  for f in "${src_dir}"/*.sh; do
    [[ -f "${f}" ]] || continue
    chmod +x "${f}"
    ln -sfn "${f}" "${dest_dir}/$(basename "${f}")"
    count=$((count + 1))
  done

  log_ok "linked ${count} Raycast scripts to ${dest_dir}"
}

main() {
  set_file_handlers
  link_raycast_scripts
}

main "$@"
