#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="dev-tools"

failed_optional=()

# Rust ecosystem tools used across recent repos.
if has_cmd rustup; then
  rustup component add rustfmt clippy llvm-tools-preview >/dev/null 2>&1 || true
fi

if has_cmd cargo; then
  if has_cmd mise; then
    ensure_cmd "alacritty" "mise exec -- cargo install --locked alacritty" "failed_optional" || true
    ensure_cmd "bacon" "mise exec -- cargo install --locked bacon" "failed_optional" || true
    ensure_cmd "cargo-nextest" "mise exec -- cargo install --locked cargo-nextest" "failed_optional" || true
    ensure_cmd "cargo-watch" "mise exec -- cargo install --locked cargo-watch" "failed_optional" || true
    ensure_cmd "trunk" "mise exec -- cargo install --locked trunk" "failed_optional" || true
    ensure_cmd "sccache" "mise exec -- cargo install --locked sccache" "failed_optional" || true
    ensure_cmd "cargo-chef" "mise exec -- cargo install --locked cargo-chef" "failed_optional" || true
    ensure_cmd "cargo-llvm-cov" "mise exec -- cargo install --locked cargo-llvm-cov" "failed_optional" || true
    ensure_cmd "cargo-deny" "mise exec -- cargo install --locked cargo-deny" "failed_optional" || true
    ensure_cmd "cargo-audit" "mise exec -- cargo install --locked cargo-audit" "failed_optional" || true
    ensure_cmd "cargo-expand" "mise exec -- cargo install --locked cargo-expand" "failed_optional" || true
    ensure_cmd "cargo-machete" "mise exec -- cargo install --locked cargo-machete" "failed_optional" || true
    ensure_cmd "cargo-criterion" "mise exec -- cargo install --locked cargo-criterion" "failed_optional" || true
    ensure_cmd "hyperfine" "mise exec -- cargo install --locked hyperfine" "failed_optional" || true
    ensure_cmd "cargo-sweep" "mise exec -- cargo install --locked cargo-sweep" "failed_optional" || true
    ensure_cmd "cargo-clean-all" "mise exec -- cargo install --locked cargo-clean-all" "failed_optional" || true
  else
    ensure_cmd "alacritty" "cargo install --locked alacritty" "failed_optional" || true
    ensure_cmd "bacon" "cargo install --locked bacon" "failed_optional" || true
    ensure_cmd "cargo-nextest" "cargo install --locked cargo-nextest" "failed_optional" || true
    ensure_cmd "cargo-watch" "cargo install --locked cargo-watch" "failed_optional" || true
    ensure_cmd "trunk" "cargo install --locked trunk" "failed_optional" || true
    ensure_cmd "sccache" "cargo install --locked sccache" "failed_optional" || true
    ensure_cmd "cargo-chef" "cargo install --locked cargo-chef" "failed_optional" || true
    ensure_cmd "cargo-llvm-cov" "cargo install --locked cargo-llvm-cov" "failed_optional" || true
    ensure_cmd "cargo-deny" "cargo install --locked cargo-deny" "failed_optional" || true
    ensure_cmd "cargo-audit" "cargo install --locked cargo-audit" "failed_optional" || true
    ensure_cmd "cargo-expand" "cargo install --locked cargo-expand" "failed_optional" || true
    ensure_cmd "cargo-machete" "cargo install --locked cargo-machete" "failed_optional" || true
    ensure_cmd "cargo-criterion" "cargo install --locked cargo-criterion" "failed_optional" || true
    ensure_cmd "hyperfine" "cargo install --locked hyperfine" "failed_optional" || true
    ensure_cmd "cargo-sweep" "cargo install --locked cargo-sweep" "failed_optional" || true
    ensure_cmd "cargo-clean-all" "cargo install --locked cargo-clean-all" "failed_optional" || true
  fi
fi

# Python workflow baseline.
if has_cmd uv; then
  log "uv available for Python project workflows"
fi

# JS workflow baseline.
if has_cmd bun; then
  log "bun available for JS/TS project workflows"
  ensure_cmd "baml-cli" "bun add -g @boundaryml/baml" "failed_optional" || true
elif has_cmd npm; then
  log "bun missing; using npm fallback for BAML CLI"
  ensure_cmd "baml-cli" "npm install -g @boundaryml/baml" "failed_optional" || true
fi

# Toolz — personal swiss-army CLI (embedded crate at dotfiles/toolz/).
if has_cmd cargo; then
  log "building toolz..."
  if cargo install --path "${ROOT_DIR}/toolz" --root "${HOME}/.local" --force >/dev/null 2>&1; then
    log_ok "toolz installed to ~/.local/bin/toolz"
  else
    log_warn "toolz build failed — skipping"
    failed_optional+=("toolz")
  fi
else
  log_warn "cargo not found; skipping toolz install"
fi

if [[ ${#failed_optional[@]} -gt 0 ]]; then
  log_warn "optional tool installs failed: ${failed_optional[*]}"
fi
log_ok "dev tool setup complete"
