#!/usr/bin/env bash
# devkit.sh — shared helpers for devkit mise tasks

# Exits 1 with a clear message if devkit is not installed.
require_devkit() {
  if ! command -v devkit &>/dev/null; then
    echo "devkit not found — run: mise run devkit-install" >&2
    exit 1
  fi
}

# Resolves the default base branch.
# Priority: DEVKIT_BASE env var > git remote HEAD > 'main'
resolve_base_branch() {
  if [[ -n "${DEVKIT_BASE:-}" ]]; then
    echo "${DEVKIT_BASE}"
    return
  fi
  local remote="${DEVKIT_REMOTE:-origin}"
  local detected
  detected="$(git remote show "${remote}" 2>/dev/null | awk '/HEAD branch/{print $NF}')"
  echo "${detected:-main}"
}
