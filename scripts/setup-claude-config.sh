#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="claude-config"

AGENTS_DIR="${HOME}/.agents"
CLAUDE_DIR="${HOME}/.claude"
SRC_DIR="${ROOT_DIR}/dot-claude"

main() {
  mkdir -p "${AGENTS_DIR}/agents" "${AGENTS_DIR}/commands" "${AGENTS_DIR}/skills"

  for subdir in agents commands skills; do
    src="${SRC_DIR}/${subdir}"
    dst="${AGENTS_DIR}/${subdir}"

    if [[ ! -d "${src}" ]]; then
      log_skip "${subdir}: no source dir"
      continue
    fi

    rsync -a --delete "${src}/" "${dst}/"
    log_ok "synced ${subdir} → ~/.agents/${subdir}"

    # Namespaced symlink: ~/.claude/agents/dotfiles → ~/.agents/agents
    link="${CLAUDE_DIR}/${subdir}/dotfiles"
    if [[ -L "${link}" ]]; then
      rm "${link}"
    fi
    ln -s "${dst}" "${link}"
    log_ok "linked ~/.claude/${subdir}/dotfiles"
  done
}

main "$@"
