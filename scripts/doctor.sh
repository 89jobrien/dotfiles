#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="doctor"

status=0

check_cmd() {
  local cmd="$1"
  if command -v "${cmd}" >/dev/null 2>&1; then
    log_ok "${cmd} -> $(command -v "${cmd}")"
  else
    log_err "${cmd} missing"
    status=1
  fi
}

check_optional_cmd() {
  local cmd="$1"
  if command -v "${cmd}" >/dev/null 2>&1; then
    log_ok "${cmd} -> $(command -v "${cmd}")"
  else
    log_skip "${cmd} (optional)"
  fi
}

log "os=$(uname -s) arch=$(uname -m)"
log "root=${ROOT_DIR}"

section "Core Commands"
for c in git curl stow nvim; do
  check_cmd "${c}"
done

section "Preferred Commands"
for c in gh opencode gemini rg fd fzf eza zoxide gum jq tmux alacritty mise zb uv bun bunx docker colima kubectl helm k9s kind k3d tilt btm btop procs duf dust tokei; do
  check_cmd "${c}"
done
check_optional_cmd "claude"
check_optional_cmd "codex"
if git flow version >/dev/null 2>&1; then
  log_ok "git-flow -> $(command -v git)"
else
  log_err "git-flow (git flow)"
  status=1
fi
check_optional_cmd "zed"
check_cmd "baml-cli"
check_optional_cmd "baml"

section "Rust Workflow"
for c in cargo rustc bacon cargo-nextest cargo-watch rust-script sccache cargo-chef cargo-llvm-cov cargo-deny cargo-audit cargo-expand cargo-machete cargo-criterion hyperfine; do
  check_cmd "${c}"
done
if [[ "$(uname -s)" == "Darwin" ]]; then
  section "macOS Commands"
  check_optional_cmd "brew"
  check_cmd "duti"
fi

section "Environment"
if [[ -f "${ROOT_DIR}/config/stow-packages.txt" ]]; then
  log_ok "stow package list present"
else
  log_err "config/stow-packages.txt missing"
  status=1
fi

if [[ -d "${HOME}/.oh-my-zsh" ]]; then
  log_ok "oh-my-zsh installed"
else
  log_warn "oh-my-zsh missing (run ./scripts/setup-oh-my-zsh.sh)"
fi

git_name="$(git config --global --get user.name || true)"
git_email="$(git config --global --get user.email || true)"
if [[ -n "${git_name}" && -n "${git_email}" ]]; then
  log_ok "git identity configured (${git_name} <${git_email}>)"
else
  log_warn "git identity incomplete (user.name/user.email)"
fi

git_gh_helper="$(git config --global --get credential.https://github.com.helper || true)"
if [[ "${git_gh_helper}" == *"gh auth git-credential"* ]]; then
  log_ok "git github helper configured"
else
  log_warn "git github helper not configured to use gh"
  log "run ./scripts/setup-git-config.sh"
fi

if command -v gh >/dev/null 2>&1; then
  if gh auth status -h github.com >/dev/null 2>&1; then
    log_ok "gh auth OK"
  else
    log_warn "gh auth not valid; pushes may fail"
  fi
fi

if [[ $status -ne 0 ]]; then
  log_err "FAIL"
  exit 1
fi

log_ok "PASS"
