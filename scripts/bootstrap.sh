#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="bootstrap"

STOW_LIST_FILE="${ROOT_DIR}/config/stow-packages.txt"
STOW_LIST_LOCAL_FILE="${ROOT_DIR}/config/stow-packages.local.txt"
APT_LIST_FILE="${ROOT_DIR}/config/apt-packages.txt"
APT_LIST_LOCAL_FILE="${ROOT_DIR}/config/apt-packages.local.txt"

DO_PACKAGES=1
DO_STOW=1
DO_POST=1

# ---------------------------------------------------------------------------
# Summary tracking
# ---------------------------------------------------------------------------

declare -a _SUMMARY_SECTIONS=()
declare -A _SUMMARY_STATUS=()
declare -A _SUMMARY_NOTE=()

_record() {
  local name="$1" status="$2" note="${3:-}"
  _SUMMARY_SECTIONS+=("${name}")
  _SUMMARY_STATUS["${name}"]="${status}"
  _SUMMARY_NOTE["${name}"]="${note}"
}

print_summary() {
  local divider="========================================"
  printf '\n%s\n' "${divider}"
  printf ' Bootstrap Summary\n'
  printf '%s\n' "${divider}"

  local any_fail=0
  for name in "${_SUMMARY_SECTIONS[@]}"; do
    local st="${_SUMMARY_STATUS[${name}]}"
    local note="${_SUMMARY_NOTE[${name}]:-}"
    local label="${st}"
    if [[ -n "${note}" ]]; then
      label="${st} (${note})"
    fi
    printf ' %-16s %s\n' "${name}" "${label}"
    if [[ "${st}" == "FAIL" ]]; then
      any_fail=1
    fi
  done
  printf '%s\n' "${divider}"
  if [[ "${any_fail}" == "1" ]]; then
    log_warn "some sections failed — check output above"
  fi
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

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
      log_err "unknown option: $arg"
      usage
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Package & stow helpers (unchanged logic)
# ---------------------------------------------------------------------------

ensure_homebrew() {
  if has_cmd zb; then
    return 0
  fi

  if has_cmd brew; then
    return 0
  fi

  if [[ "$(uname -s)" == "Darwin" ]]; then
    log "installing Homebrew (macOS)..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    return 0
  fi

  if [[ "$(uname -s)" == "Linux" ]]; then
    log "Homebrew is not installed on Linux; falling back to apt when available"
    return 1
  fi

  log_err "unsupported OS for automatic Homebrew install: $(uname -s)"
  return 1
}

check_homebrew_writable() {
  if has_cmd zb; then
    return 0
  fi

  if ! has_cmd brew; then
    return 0
  fi

  local brew_prefix
  brew_prefix="$(brew --prefix 2>/dev/null || true)"
  if [[ -z "${brew_prefix}" ]]; then
    return 0
  fi

  if [[ ! -w "${brew_prefix}" || ! -w "${brew_prefix}/bin" ]]; then
    log_err "Homebrew prefix is not writable: ${brew_prefix}"
    log "run this once and retry:"
    log "  sudo chown -R $(whoami) ${brew_prefix}"
    return 1
  fi
}

ensure_stow() {
  if has_cmd stow; then
    return 0
  fi

  if has_cmd zb; then
    log "installing stow via zerobrew..."
    zb install stow
    return 0
  fi

  if has_cmd brew; then
    log "installing stow via Homebrew..."
    brew install stow
    return 0
  fi

  if [[ "$(uname -s)" == "Linux" ]] && has_cmd apt-get; then
    log "installing stow via apt..."
    sudo apt-get update
    sudo apt-get install -y stow
    return 0
  fi

  log_err "cannot install stow automatically"
  return 1
}

install_packages() {
  if [[ "$DO_PACKAGES" -ne 1 ]]; then
    log_skip "package install"
    return 0
  fi

  local brew_compat_cmd=""
  local brew_compat_name=""
  if has_cmd zb; then
    brew_compat_cmd="zb"
    brew_compat_name="zerobrew"
  elif has_cmd brew; then
    brew_compat_cmd="brew"
    brew_compat_name="brew"
  fi

  if [[ -n "${brew_compat_cmd}" ]]; then
    local brewfile="${ROOT_DIR}/Brewfile"
    if [[ "$(uname -s)" == "Darwin" && -f "${ROOT_DIR}/Brewfile.macos" ]]; then
      brewfile="${ROOT_DIR}/Brewfile.macos"
    elif [[ "$(uname -s)" == "Linux" && -f "${ROOT_DIR}/Brewfile.linux" ]]; then
      brewfile="${ROOT_DIR}/Brewfile.linux"
    fi

    if [[ -f "${brewfile}" ]]; then
      log "installing packages via ${brew_compat_name} bundle (${brewfile##*/})..."
      if [[ "${brew_compat_cmd}" == "zb" ]]; then
        if ! "${brew_compat_cmd}" bundle install --file "${brewfile}"; then
          if has_cmd brew; then
            log_warn "zerobrew bundle failed; falling back to brew bundle"
            brew bundle --file "${brewfile}"
          else
            return 1
          fi
        fi
      else
        "${brew_compat_cmd}" bundle --file "${brewfile}"
      fi
    fi
    return 0
  fi

  if [[ "$(uname -s)" == "Linux" ]] && has_cmd apt-get; then
    if [[ -f "${APT_LIST_FILE}" ]]; then
      log "installing fallback packages via apt..."
      # shellcheck disable=SC2046
      sudo apt-get update && sudo apt-get install -y $(grep -Ev '^\s*(#|$)' "${APT_LIST_FILE}")
      if [[ -f "${APT_LIST_LOCAL_FILE}" ]]; then
        # shellcheck disable=SC2046
        sudo apt-get install -y $(grep -Ev '^\s*(#|$)' "${APT_LIST_LOCAL_FILE}")
      fi
    fi
    return 0
  fi

  log_warn "no supported package manager found; skipping package install"
}

install_mise_toolchain() {
  if ! has_cmd mise; then
    log_skip "mise not found; skipping mise-managed runtime install"
    return 0
  fi

  if [[ -f "${ROOT_DIR}/.mise.toml" ]]; then
    log "installing runtimes/tools via mise..."
    (cd "${ROOT_DIR}" && mise install)
  fi
}

stow_package() {
  local package="$1"
  if [[ ! -d "${ROOT_DIR}/${package}" ]]; then
    log_skip "package '${package}' not found"
    return 0
  fi

  local dry_run_output
  dry_run_output="$(stow -d "${ROOT_DIR}" -t "${HOME}" -n "${package}" 2>&1 || true)"
  if printf '%s\n' "${dry_run_output}" | grep -Eq 'would cause conflicts|cannot stow|existing target is not owned by stow|ERROR'; then
    log_warn "conflict detected in '${package}'; run 'pj dot adopt' and rerun"
    return 0
  fi

  log "stowing ${package}..."
  stow -d "${ROOT_DIR}" -t "${HOME}" -R "${package}"
}

stow_packages() {
  if [[ "$DO_STOW" -ne 1 ]]; then
    log_skip "stow"
    return 0
  fi

  if [[ ! -f "${STOW_LIST_FILE}" ]]; then
    log_err "missing stow package list: ${STOW_LIST_FILE}"
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

# ---------------------------------------------------------------------------
# Post-setup hooks (consolidated: 12 → 7 scripts)
# ---------------------------------------------------------------------------

run_hook() {
  local section_name="$1"
  shift
  local rc=0
  "$@" || rc=$?
  if [[ $rc -eq 0 ]]; then
    _record "${section_name}" "ok"
  else
    _record "${section_name}" "FAIL"
  fi
  return 0
}

run_post_hooks() {
  if [[ "$DO_POST" -ne 1 ]]; then
    log_skip "post-setup hooks"
    return 0
  fi

  section "Shell"
  run_hook "Shell" "${ROOT_DIR}/scripts/setup-git-config.sh"
  run_hook "Oh-My-Zsh" "${ROOT_DIR}/scripts/setup-oh-my-zsh.sh"

  section "Secrets"
  run_hook "Secrets" "${ROOT_DIR}/scripts/setup-secrets.sh"

  section "Nix"
  run_hook "Nix" "${ROOT_DIR}/scripts/setup-nix.sh"

  if [[ "$(uname -s)" == "Darwin" ]]; then
    section "macOS"
    run_hook "macOS" "${ROOT_DIR}/scripts/setup-macos.sh"
  fi

  section "AI Tools"
  run_hook "AI Tools" "${ROOT_DIR}/scripts/setup-ai-tools.sh"
  run_hook "Hooks" "${ROOT_DIR}/scripts/setup-hooks.sh"

  section "Maestro"
  run_hook "Maestro" "${ROOT_DIR}/scripts/setup-maestro.sh"

  section "Companion Repos"
  run_hook "Companion Repos" "${ROOT_DIR}/scripts/setup-companion-repos.sh"

  section "Dev Tools"
  if has_cmd mise && [[ -f "${ROOT_DIR}/.mise.toml" ]]; then
    run_hook "Dev Tools" sh -c "cd '${ROOT_DIR}' && mise run dev-tools"
  else
    run_hook "Dev Tools" "${ROOT_DIR}/scripts/setup-dev-tools.sh"
  fi

  section "Editor"
  run_hook "Editor" "${ROOT_DIR}/scripts/setup-nvchad-avante.sh"

  if [[ -x "${ROOT_DIR}/scripts/post-bootstrap.local.sh" ]]; then
    section "Local"
    run_hook "Local" "${ROOT_DIR}/scripts/post-bootstrap.local.sh"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  cd "${ROOT_DIR}"
  log "starting bootstrap on $(uname -s)"
  "${ROOT_DIR}/scripts/setup-zerobrew.sh" || true
  ensure_homebrew || true
  check_homebrew_writable
  install_packages
  "${ROOT_DIR}/scripts/setup-npm-tools.sh" || true
  install_mise_toolchain
  stow_packages
  run_post_hooks
  print_summary
  log_ok "bootstrap complete"
}

main
