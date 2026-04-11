#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="direnv"

# Inject a block into a file if the marker string is not already present.
# Usage: inject_if_absent <file> <marker> <block>
inject_if_absent() {
  local file="$1"
  local marker="$2"
  local block="$3"

  if [[ ! -f "$file" ]]; then
    log_warn "target file not found, skipping: $file"
    return 0
  fi

  if grep -qF "$marker" "$file" 2>/dev/null; then
    log_skip "already present in $(basename "$file"): $marker"
    return 0
  fi

  printf '\n%s\n' "$block" >> "$file"
  log_ok "injected direnv hook into $(basename "$file")"
}

main() {
  if ! has_cmd direnv; then
    log_skip "direnv not found on PATH — install via Homebrew or Nix first"
    return 0
  fi

  log_ok "direnv found: $(direnv version)"

  # --- zsh hook (must come after mise activate in .zshrc) ---
  inject_if_absent \
    "${HOME}/.zshrc" \
    "direnv hook zsh" \
    '# direnv integration
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi'

  # --- fish hook ---
  inject_if_absent \
    "${HOME}/.config/fish/config.fish" \
    "direnv hook fish" \
    '# direnv integration
if command -q direnv
    direnv hook fish | source
end'

  # --- nushell hook ---
  inject_if_absent \
    "${HOME}/.config/nushell/config.nu" \
    "direnv export json" \
    '# direnv integration
$env.config = ($env.config? | default {} | upsert hooks (
  $env.config?.hooks? | default {} | upsert pre_prompt (
    ($env.config?.hooks?.pre_prompt? | default []) | append {||
      if (which direnv | is-empty) { return }
      direnv export json | from json | load-env
    }
  )
))'

  # --- auto-allow workspace .envrc files ---
  local -a envrc_paths=(
    "${HOME}/dev/.envrc"
    "${HOME}/dev/dotfiles/.envrc"
  )
  for envrc in "${envrc_paths[@]}"; do
    if [[ -f "$envrc" ]]; then
      direnv allow "$envrc" 2>/dev/null && log_ok "allowed: $envrc" || log_warn "direnv allow failed for: $envrc"
    else
      log_skip "not found (skipping allow): $envrc"
    fi
  done
}

main "$@"
