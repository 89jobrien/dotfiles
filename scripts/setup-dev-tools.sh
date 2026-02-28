#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[dev-tools] %s\n' "$*"
}

ensure_cmd() {
  local cmd="$1"
  local install_cmd="$2"
  if command -v "${cmd}" >/dev/null 2>&1; then
    return 0
  fi
  log "Installing ${cmd}..."
  if ! eval "${install_cmd}"; then
    log "Failed to install ${cmd}; continuing."
    return 1
  fi
}

# Rust ecosystem tools used across recent repos.
if command -v rustup >/dev/null 2>&1; then
  rustup component add rustfmt clippy llvm-tools-preview >/dev/null 2>&1 || true
fi

if command -v cargo >/dev/null 2>&1; then
  if command -v mise >/dev/null 2>&1; then
    ensure_cmd "bacon" "mise exec -- cargo install --locked bacon"
    ensure_cmd "cargo-nextest" "mise exec -- cargo install --locked cargo-nextest"
    ensure_cmd "cargo-watch" "mise exec -- cargo install --locked cargo-watch"
    ensure_cmd "trunk" "mise exec -- cargo install --locked trunk"
    ensure_cmd "sccache" "mise exec -- cargo install --locked sccache"
    ensure_cmd "cargo-chef" "mise exec -- cargo install --locked cargo-chef"
    ensure_cmd "cargo-binstall" "mise exec -- cargo install --locked cargo-binstall"
    ensure_cmd "cargo-llvm-cov" "mise exec -- cargo install --locked cargo-llvm-cov"
    ensure_cmd "cargo-deny" "mise exec -- cargo install --locked cargo-deny"
    ensure_cmd "cargo-audit" "mise exec -- cargo install --locked cargo-audit"
    ensure_cmd "cargo-outdated" "mise exec -- cargo install --locked cargo-outdated"
    ensure_cmd "cargo-expand" "mise exec -- cargo install --locked cargo-expand"
    ensure_cmd "cargo-machete" "mise exec -- cargo install --locked cargo-machete"
    ensure_cmd "cargo-criterion" "mise exec -- cargo install --locked cargo-criterion"
    ensure_cmd "hyperfine" "mise exec -- cargo install --locked hyperfine"
  else
    ensure_cmd "bacon" "cargo install --locked bacon"
    ensure_cmd "cargo-nextest" "cargo install --locked cargo-nextest"
    ensure_cmd "cargo-watch" "cargo install --locked cargo-watch"
    ensure_cmd "trunk" "cargo install --locked trunk"
    ensure_cmd "sccache" "cargo install --locked sccache"
    ensure_cmd "cargo-chef" "cargo install --locked cargo-chef"
    ensure_cmd "cargo-binstall" "cargo install --locked cargo-binstall"
    ensure_cmd "cargo-llvm-cov" "cargo install --locked cargo-llvm-cov"
    ensure_cmd "cargo-deny" "cargo install --locked cargo-deny"
    ensure_cmd "cargo-audit" "cargo install --locked cargo-audit"
    ensure_cmd "cargo-outdated" "cargo install --locked cargo-outdated"
    ensure_cmd "cargo-expand" "cargo install --locked cargo-expand"
    ensure_cmd "cargo-machete" "cargo install --locked cargo-machete"
    ensure_cmd "cargo-criterion" "cargo install --locked cargo-criterion"
    ensure_cmd "hyperfine" "cargo install --locked hyperfine"
  fi
fi

# Python workflow baseline.
if command -v uv >/dev/null 2>&1; then
  log "uv available for Python project workflows."
fi

# JS workflow baseline.
if command -v bun >/dev/null 2>&1; then
  log "bun available for JS/TS project workflows."
fi

log "Dev tool setup complete."
