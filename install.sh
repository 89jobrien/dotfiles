#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${PJ_DOTFILES_RUNNER:-}" != "pj" && "${ALLOW_DIRECT_DOTFILES_INSTALL:-0}" != "1" ]]; then
  if command -v pj >/dev/null 2>&1; then
    exec pj dot install "$@"
  fi

  echo "[install] pj not found on PATH; dotfiles bootstrap is managed by pj."

  pj_source=""
  for candidate in "${HOME}/dev/pj" "${HOME}/pj"; do
    if [[ -f "${candidate}/Cargo.toml" ]]; then
      pj_source="${candidate}"
      break
    fi
  done

  if [[ -n "${pj_source}" && -t 0 ]]; then
    if command -v cargo >/dev/null 2>&1; then
      read -r -p "[install] Install pj from ${pj_source}? [Y/n] " reply
      reply="${reply:-Y}"
      case "${reply}" in
        [Yy]|[Yy][Ee][Ss])
          echo "[install] Installing pj..."
          cargo install --path "${pj_source}"
          hash -r
          if command -v pj >/dev/null 2>&1; then
            exec pj dot install "$@"
          fi
          ;;
      esac
    else
      echo "[install] cargo not found; cannot auto-install pj."
    fi
  fi

  echo "[install] Manual steps:"
  if [[ -n "${pj_source}" ]]; then
    echo "[install]   cargo install --path ${pj_source}"
  else
    echo "[install]   clone/build pj, then run: cargo install --path /path/to/pj"
  fi
  echo "[install]   then run: pj dot install"
  echo "[install] Bypass once: ALLOW_DIRECT_DOTFILES_INSTALL=1 ./install.sh"
  exit 1
fi

exec "${ROOT_DIR}/scripts/bootstrap.sh" "$@"
