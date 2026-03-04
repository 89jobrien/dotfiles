#!/usr/bin/env bash
# Package manager detection and utilities for dotfiles bootstrap scripts.
# Source this file after log.sh.
#
# Usage:
#   source "${ROOT_DIR}/scripts/lib/log.sh"
#   source "${ROOT_DIR}/scripts/lib/pkg.sh"
#   TAG="my-script"
#
#   detect_pkg_manager           # prints "zerobrew", "homebrew", "apt", or ""
#   has_zerobrew                 # returns 0 if zb exists
#   has_brew                     # returns 0 if brew exists
#   has_apt                      # returns 0 if apt exists

# has_zerobrew
#   Returns 0 if zerobrew (zb) is available
has_zerobrew() {
  command -v zb >/dev/null 2>&1
}

# has_brew
#   Returns 0 if Homebrew is available
has_brew() {
  command -v brew >/dev/null 2>&1
}

# has_apt
#   Returns 0 if apt (Debian/Ubuntu) is available
has_apt() {
  command -v apt >/dev/null 2>&1
}

# detect_pkg_manager
#   Detect available package manager in priority order: zb > brew > apt
#   Prints: "zerobrew", "homebrew", "apt", or "" (empty if none found)
detect_pkg_manager() {
  if has_zerobrew; then
    echo "zerobrew"
  elif has_brew; then
    echo "homebrew"
  elif has_apt; then
    echo "apt"
  else
    echo ""
  fi
}

# ensure_homebrew
#   Check if zerobrew or Homebrew is available. Exit if neither found.
ensure_homebrew() {
  if has_zerobrew; then
    return 0
  fi

  if has_brew; then
    return 0
  fi

  log_err "neither zerobrew nor Homebrew found"
  log "install Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  exit 1
}

# bundle_install BREWFILE_PATH
#   Install packages from a Brewfile using zb (preferred) or brew.
#   Returns 0 on success, 1 on failure.
bundle_install() {
  local brewfile="$1"

  if [[ ! -f "${brewfile}" ]]; then
    log_err "Brewfile not found: ${brewfile}"
    return 1
  fi

  if has_zerobrew; then
    log "installing packages via zerobrew bundle..."
    zb bundle --file "${brewfile}"
  elif has_brew; then
    log "installing packages via brew bundle..."
    brew bundle --file "${brewfile}"
  else
    log_err "no package manager found (zb or brew)"
    return 1
  fi
}
