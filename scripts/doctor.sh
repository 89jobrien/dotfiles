#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

status=0

check_cmd() {
  local cmd="$1"
  if command -v "${cmd}" >/dev/null 2>&1; then
    printf '[ok] %s -> %s\n' "${cmd}" "$(command -v "${cmd}")"
  else
    printf '[missing] %s\n' "${cmd}"
    status=1
  fi
}

check_optional_cmd() {
  local cmd="$1"
  if command -v "${cmd}" >/dev/null 2>&1; then
    printf '[ok] %s -> %s\n' "${cmd}" "$(command -v "${cmd}")"
  else
    printf '[optional-missing] %s\n' "${cmd}"
  fi
}

echo "[doctor] os=$(uname -s) arch=$(uname -m)"
echo "[doctor] root=${ROOT_DIR}"

echo "[doctor] core commands"
for c in git curl stow nvim; do
  check_cmd "${c}"
done

echo "[doctor] preferred commands"
for c in gh rg fd jq tmux alacritty mise zb uv bun bunx docker colima kubectl helm k9s kind k3d tilt; do
  check_cmd "${c}"
done

echo "[doctor] rust workflow commands"
for c in cargo rustc bacon cargo-nextest cargo-watch sccache cargo-chef cargo-llvm-cov cargo-deny cargo-audit cargo-expand cargo-machete cargo-criterion hyperfine; do
  check_cmd "${c}"
done
check_optional_cmd "cargo-binstall"
check_optional_cmd "cargo-outdated"

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "[doctor] macOS commands"
  for c in brew duti; do
    check_cmd "${c}"
  done
fi

if [[ -f "${ROOT_DIR}/config/stow-packages.txt" ]]; then
  echo "[doctor] stow package list present"
else
  echo "[missing] config/stow-packages.txt"
  status=1
fi

if [[ $status -ne 0 ]]; then
  echo "[doctor] FAIL"
  exit 1
fi

echo "[doctor] PASS"
