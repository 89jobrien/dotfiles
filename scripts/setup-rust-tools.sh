#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="rust-tools"

failed_optional=()

if has_cmd rustup; then
  rustup component add rustfmt clippy llvm-tools-preview >/dev/null 2>&1 || true
fi

if ! has_cmd cargo; then
  log_warn "cargo not found; skipping rust tools"
  exit 0
fi

# Resolve cargo runner (prefer mise-managed rust for correct toolchain)
if has_cmd mise; then
  cargo_cmd="mise exec -- cargo"
else
  cargo_cmd="cargo"
fi

tools=(
  alacritty
  bacon
  trunk
  sccache
  cargo-chef
  cargo-llvm-cov
  cargo-deny
  cargo-audit
  cargo-expand
  cargo-machete
  cargo-criterion
  hyperfine
  cargo-sweep
  cargo-clean-all
)

for tool in "${tools[@]}"; do
  ensure_cmd "${tool}" "${cargo_cmd} install --locked ${tool}" "failed_optional" || true
done

# Companion repo builds (toolz, obfsck)
for repo_path in "${HOME}/dev/tools" "${HOME}/dev/obfsck"; do
  if [[ -d "${repo_path}" ]]; then
    name="$(basename "${repo_path}")"
    log "building ${name}..."
    # shellcheck disable=SC2086
    if ${cargo_cmd} install --path "${repo_path}" --root "${HOME}/.local" --force >/dev/null 2>&1; then
      log_ok "${name} installed to ~/.local/bin/${name}"
    else
      log_warn "${name} build failed — skipping"
      failed_optional+=("${name}")
    fi
  fi
done

if [[ ${#failed_optional[@]} -gt 0 ]]; then
  log_warn "optional tool installs failed: ${failed_optional[*]}"
fi
log_ok "rust tools setup complete"
