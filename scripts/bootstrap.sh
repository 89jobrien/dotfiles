#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STOW_LIST_FILE="${ROOT_DIR}/config/stow-packages.txt"
STOW_LIST_LOCAL_FILE="${ROOT_DIR}/config/stow-packages.local.txt"
APT_LIST_FILE="${ROOT_DIR}/config/apt-packages.txt"
APT_LIST_LOCAL_FILE="${ROOT_DIR}/config/apt-packages.local.txt"

DO_PACKAGES=1
DO_STOW=1
DO_POST=1

log() {
  printf '[bootstrap] %s\n' "$*"
}

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --no-packages   Skip package manager installs
  --no-stow       Skip stow linking
  --no-post       Skip post-setup hooks
  -h, --help      Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --no-packages) DO_PACKAGES=0 ;;
    --no-stow) DO_STOW=0 ;;
    --no-post) DO_POST=0 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log "Unknown option: $arg"
      usage
      exit 1
      ;;
  esac
done

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$(uname -s)" == "Darwin" ]]; then
    log "Installing Homebrew (macOS)..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    return 0
  fi

  if [[ "$(uname -s)" == "Linux" ]]; then
    log "Homebrew is not installed on Linux. Falling back to apt when available."
    return 1
  fi

  log "Unsupported OS for automatic Homebrew install: $(uname -s)"
  return 1
}

check_homebrew_writable() {
  if ! command -v brew >/dev/null 2>&1; then
    return 0
  fi

  local brew_prefix
  brew_prefix="$(brew --prefix 2>/dev/null || true)"
  if [[ -z "${brew_prefix}" ]]; then
    return 0
  fi

  if [[ ! -w "${brew_prefix}" || ! -w "${brew_prefix}/bin" ]]; then
    log "Homebrew prefix is not writable: ${brew_prefix}"
    log "Run this once and retry:"
    log "  sudo chown -R $(whoami) ${brew_prefix}"
    return 1
  fi
}

ensure_stow() {
  if command -v stow >/dev/null 2>&1; then
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    log "Installing stow via Homebrew..."
    brew install stow
    return 0
  fi

  if [[ "$(uname -s)" == "Linux" ]] && command -v apt-get >/dev/null 2>&1; then
    log "Installing stow via apt..."
    sudo apt-get update
    sudo apt-get install -y stow
    return 0
  fi

  log "Cannot install stow automatically."
  return 1
}

install_packages() {
  if [[ "$DO_PACKAGES" -ne 1 ]]; then
    log "Skipping package install."
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    local brewfile="${ROOT_DIR}/Brewfile"
    if [[ "$(uname -s)" == "Darwin" && -f "${ROOT_DIR}/Brewfile.macos" ]]; then
      brewfile="${ROOT_DIR}/Brewfile.macos"
    elif [[ "$(uname -s)" == "Linux" && -f "${ROOT_DIR}/Brewfile.linux" ]]; then
      brewfile="${ROOT_DIR}/Brewfile.linux"
    fi

    if [[ -f "${brewfile}" ]]; then
      log "Installing packages via brew bundle (${brewfile##*/})..."
      brew bundle --file "${brewfile}"
    fi
    return 0
  fi

  if [[ "$(uname -s)" == "Linux" ]] && command -v apt-get >/dev/null 2>&1; then
    if [[ -f "${APT_LIST_FILE}" ]]; then
      log "Installing fallback packages via apt..."
      # shellcheck disable=SC2046
      sudo apt-get update && sudo apt-get install -y $(grep -Ev '^\s*(#|$)' "${APT_LIST_FILE}")
      if [[ -f "${APT_LIST_LOCAL_FILE}" ]]; then
        # shellcheck disable=SC2046
        sudo apt-get install -y $(grep -Ev '^\s*(#|$)' "${APT_LIST_LOCAL_FILE}")
      fi
    fi
    return 0
  fi

  log "No supported package manager found. Skipping package install."
}

install_mise_toolchain() {
  if ! command -v mise >/dev/null 2>&1; then
    log "mise not found, skipping mise-managed runtime install."
    return 0
  fi

  if [[ -f "${ROOT_DIR}/.mise.toml" ]]; then
    log "Installing runtimes/tools via mise..."
    (cd "${ROOT_DIR}" && mise install)
  fi
}

stow_package() {
  local package="$1"
  if [[ ! -d "${ROOT_DIR}/${package}" ]]; then
    log "Package '${package}' not found; skipping."
    return 0
  fi

  local dry_run_output
  dry_run_output="$(stow -d "${ROOT_DIR}" -t "${HOME}" -n "${package}" 2>&1 || true)"
  if printf '%s\n' "${dry_run_output}" | grep -Eq 'would cause conflicts|cannot stow|existing target is not owned by stow|ERROR'; then
    log "Conflict detected in '${package}'. Run 'pj dot adopt' and rerun."
    return 0
  fi

  log "Stowing ${package}..."
  stow -d "${ROOT_DIR}" -t "${HOME}" -R "${package}"
}

stow_packages() {
  if [[ "$DO_STOW" -ne 1 ]]; then
    log "Skipping stow."
    return 0
  fi

  if [[ ! -f "${STOW_LIST_FILE}" ]]; then
    log "Missing stow package list: ${STOW_LIST_FILE}"
    return 1
  fi

  ensure_stow
  while IFS= read -r pkg; do
    [[ -z "${pkg}" || "${pkg}" =~ ^[[:space:]]*# ]] && continue
    stow_package "${pkg}"
  done < "${STOW_LIST_FILE}"

  if [[ -f "${STOW_LIST_LOCAL_FILE}" ]]; then
    while IFS= read -r pkg; do
      [[ -z "${pkg}" || "${pkg}" =~ ^[[:space:]]*# ]] && continue
      stow_package "${pkg}"
    done < "${STOW_LIST_LOCAL_FILE}"
  fi
}

run_post_hooks() {
  if [[ "$DO_POST" -ne 1 ]]; then
    log "Skipping post-setup hooks."
    return 0
  fi

  "${ROOT_DIR}/scripts/setup-git-config.sh" || true
  "${ROOT_DIR}/scripts/setup-oh-my-zsh.sh" || true

  "${ROOT_DIR}/scripts/setup-secrets.sh" || true
  "${ROOT_DIR}/scripts/setup-secret-hygiene.sh" || true

  "${ROOT_DIR}/scripts/setup-alacritty-source.sh" || true

  if [[ "$(uname -s)" == "Darwin" ]]; then
    "${ROOT_DIR}/scripts/macos-defaults.sh" || true
    "${ROOT_DIR}/scripts/setup-raycast-scripts.sh" || true
  fi

  "${ROOT_DIR}/scripts/setup-personal-mcp.sh" || true

  if command -v mise >/dev/null 2>&1 && [[ -f "${ROOT_DIR}/.mise.toml" ]]; then
    (cd "${ROOT_DIR}" && mise run dev-tools) || true
  else
    "${ROOT_DIR}/scripts/setup-dev-tools.sh" || true
  fi
  "${ROOT_DIR}/scripts/setup-nvchad-avante.sh" || true

  if [[ -x "${ROOT_DIR}/scripts/post-bootstrap.local.sh" ]]; then
    log "Running local post-bootstrap hook..."
    "${ROOT_DIR}/scripts/post-bootstrap.local.sh"
  fi
}

main() {
  cd "${ROOT_DIR}"
  log "Starting bootstrap on $(uname -s)"
  "${ROOT_DIR}/scripts/setup-zerobrew.sh" || true
  ensure_homebrew || true
  check_homebrew_writable
  install_packages
  install_mise_toolchain
  stow_packages
  run_post_hooks
  log "Bootstrap complete."
}

main
