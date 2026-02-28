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
for c in gh rg fd fzf eza zoxide gum jq tmux alacritty mise zb uv bun bunx docker colima kubectl helm k9s kind k3d tilt btm btop procs duf dust; do
  check_cmd "${c}"
done
if git flow version >/dev/null 2>&1; then
  echo "[ok] git-flow -> $(command -v git)"
else
  echo "[missing] git-flow (git flow)"
  status=1
fi
check_optional_cmd "zed"
check_optional_cmd "baml-cli"

echo "[doctor] rust workflow commands"
for c in cargo rustc bacon cargo-nextest cargo-watch sccache cargo-chef cargo-llvm-cov cargo-deny cargo-audit cargo-expand cargo-machete cargo-criterion hyperfine; do
  check_cmd "${c}"
done
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

if [[ -d "${HOME}/.oh-my-zsh" ]]; then
  echo "[doctor] oh-my-zsh installed"
else
  echo "[doctor] warning: oh-my-zsh missing (run ./scripts/setup-oh-my-zsh.sh)"
fi

git_name="$(git config --global --get user.name || true)"
git_email="$(git config --global --get user.email || true)"
if [[ -n "${git_name}" && -n "${git_email}" ]]; then
  echo "[doctor] git identity configured (${git_name} <${git_email}>)"
else
  echo "[doctor] warning: git identity incomplete (user.name/user.email)"
fi

git_gh_helper="$(git config --global --get credential.https://github.com.helper || true)"
if [[ "${git_gh_helper}" == *"gh auth git-credential"* ]]; then
  echo "[doctor] git github helper configured (${git_gh_helper})"
else
  echo "[doctor] warning: git github helper not configured to use gh"
  echo "[doctor]         run ./scripts/setup-git-config.sh"
fi

if command -v gh >/dev/null 2>&1; then
  if gh auth status -h github.com >/dev/null 2>&1; then
    echo "[doctor] gh auth OK"
  else
    echo "[doctor] warning: gh auth not valid; pushes may fail"
  fi
fi

if [[ $status -ne 0 ]]; then
  echo "[doctor] FAIL"
  exit 1
fi

echo "[doctor] PASS"
