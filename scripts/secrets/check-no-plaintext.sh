#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log() {
  printf '[secrets-check] %s\n' "$*"
}

if ! git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "Not inside a git repository."
  exit 1
fi

cd "${ROOT_DIR}"

# 1) Block known plaintext secret file paths from being staged.
forbidden_paths='(^|/)(\.env|\.env\.local|mise\.local\.toml|secrets/\.env\.json|secrets/bootstrap\.env)$'
staged_paths="$(git diff --cached --name-only --diff-filter=ACMRTUXB || true)"
if printf '%s\n' "${staged_paths}" | rg -n "${forbidden_paths}" >/dev/null 2>&1; then
  log "Plaintext secret file staged. Use encrypted/sops paths only."
  printf '%s\n' "${staged_paths}" | rg -n "${forbidden_paths}" || true
  exit 1
fi

# 2) Block plaintext-looking secret assignments in staged diff.
# Skip `*.example` files so placeholder templates can be committed.
# Catch env-style (`KEY=value`) and JSON/YAML config-style assignments.
staged_diff="$(git diff --cached --text --unified=0 -- . ':(exclude)*.example' || true)"
added_lines="$(printf '%s\n' "${staged_diff}" | rg '^\+' | rg -v '^\+\+\+' || true)"
content_pattern_env='^\+\s*[A-Z0-9_]*(API[_-]?KEY|TOKEN|PASSWORD|PASSWD|SECRET(_ACCESS)?_KEY|DATABASE_URL|REDIS_URL)[A-Z0-9_]*\s*=\s*[^[:space:]#]+'
# Config-style secrets: require either a quoted key or an ALL_CAPS key.
content_pattern_config='^\+\s*(["'"'"'][A-Za-z0-9_]*(api[_-]?key|token|password|passwd|secret(_access)?_key|database[_-]?url|redis[_-]?url)["'"'"']|[A-Z0-9_]*(API[_-]?KEY|TOKEN|PASSWORD|PASSWD|SECRET(_ACCESS)?_KEY|DATABASE_URL|REDIS_URL)[A-Z0-9_]*)\s*:\s*["'"'"']?[^\s,"'"'"']+'
if printf '%s\n' "${added_lines}" | rg -e "${content_pattern_env}" -e "${content_pattern_config}" >/dev/null 2>&1; then
  log "Potential plaintext secrets found in staged diff."
  printf '%s\n' "${added_lines}" | rg -e "${content_pattern_env}" -e "${content_pattern_config}" || true
  exit 1
fi

log "No plaintext secret files/content detected."
