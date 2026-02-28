#!/usr/bin/env bash
set -euo pipefail

failed_optional=()

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
    failed_optional+=("${cmd}")
    return 1
  fi
}

# Rust ecosystem tools used across recent repos.
if command -v rustup >/dev/null 2>&1; then
  rustup component add rustfmt clippy llvm-tools-preview >/dev/null 2>&1 || true
fi

if command -v cargo >/dev/null 2>&1; then
  if command -v mise >/dev/null 2>&1; then
    ensure_cmd "bacon" "mise exec -- cargo install --locked bacon" || true
    ensure_cmd "cargo-nextest" "mise exec -- cargo install --locked cargo-nextest" || true
    ensure_cmd "cargo-watch" "mise exec -- cargo install --locked cargo-watch" || true
    ensure_cmd "trunk" "mise exec -- cargo install --locked trunk" || true
    ensure_cmd "sccache" "mise exec -- cargo install --locked sccache" || true
    ensure_cmd "cargo-chef" "mise exec -- cargo install --locked cargo-chef" || true
    ensure_cmd "cargo-llvm-cov" "mise exec -- cargo install --locked cargo-llvm-cov" || true
    ensure_cmd "cargo-deny" "mise exec -- cargo install --locked cargo-deny" || true
    ensure_cmd "cargo-audit" "mise exec -- cargo install --locked cargo-audit" || true
    ensure_cmd "cargo-expand" "mise exec -- cargo install --locked cargo-expand" || true
    ensure_cmd "cargo-machete" "mise exec -- cargo install --locked cargo-machete" || true
    ensure_cmd "cargo-criterion" "mise exec -- cargo install --locked cargo-criterion" || true
    ensure_cmd "hyperfine" "mise exec -- cargo install --locked hyperfine" || true
  else
    ensure_cmd "bacon" "cargo install --locked bacon" || true
    ensure_cmd "cargo-nextest" "cargo install --locked cargo-nextest" || true
    ensure_cmd "cargo-watch" "cargo install --locked cargo-watch" || true
    ensure_cmd "trunk" "cargo install --locked trunk" || true
    ensure_cmd "sccache" "cargo install --locked sccache" || true
    ensure_cmd "cargo-chef" "cargo install --locked cargo-chef" || true
    ensure_cmd "cargo-llvm-cov" "cargo install --locked cargo-llvm-cov" || true
    ensure_cmd "cargo-deny" "cargo install --locked cargo-deny" || true
    ensure_cmd "cargo-audit" "cargo install --locked cargo-audit" || true
    ensure_cmd "cargo-expand" "cargo install --locked cargo-expand" || true
    ensure_cmd "cargo-machete" "cargo install --locked cargo-machete" || true
    ensure_cmd "cargo-criterion" "cargo install --locked cargo-criterion" || true
    ensure_cmd "hyperfine" "cargo install --locked hyperfine" || true
  fi
fi

# Python workflow baseline.
if command -v uv >/dev/null 2>&1; then
  log "uv available for Python project workflows."
fi

# JS workflow baseline.
if command -v bun >/dev/null 2>&1; then
  log "bun available for JS/TS project workflows."
  ensure_cmd "baml-cli" "bun add -g @boundaryml/baml" || true
elif command -v npm >/dev/null 2>&1; then
  log "bun missing; using npm fallback for BAML CLI."
  ensure_cmd "baml-cli" "npm install -g @boundaryml/baml" || true
fi

if [[ ${#failed_optional[@]} -gt 0 ]]; then
  log "Optional tool installs failed: ${failed_optional[*]}"
fi
log "Dev tool setup complete."
