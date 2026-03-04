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
# Catch both env-style (`KEY=value`) and JSON/YAML-style (`"KEY": "value"`).
staged_diff="$(git diff --cached --text --unified=0 || true)"
added_lines="$(printf '%s\n' "${staged_diff}" | rg '^\+' | rg -v '^\+\+\+' || true)"
content_pattern_primary='["'"'"']?(openai[_-]?api[_-]?key|anthropic[_-]?api[_-]?key|gemini[_-]?api[_-]?key|tavily[_-]?api[_-]?key|context7[_-]?api[_-]?key|boundary[_-]?api[_-]?key|github[_-]?token|gh[_-]?token|aws[_-]?access[_-]?key[_-]?id|aws[_-]?secret[_-]?access[_-]?key|database[_-]?url|redis[_-]?url)["'"'"']?\s*[:=]\s*["'"'"']?[^\s,"'"'"']+'
content_pattern_generic='["'"'"']?[a-z0-9_]*(api[_-]?key|token|password|passwd|secret(_access)?_key)[a-z0-9_]*["'"'"']?\s*[:=]\s*["'"'"']?[^\s,"'"'"']+'
if printf '%s\n' "${added_lines}" | rg -i -e "${content_pattern_primary}" -e "${content_pattern_generic}" >/dev/null 2>&1; then
  log "Potential plaintext secrets found in staged diff."
  printf '%s\n' "${added_lines}" | rg -i -e "${content_pattern_primary}" -e "${content_pattern_generic}" || true
  exit 1
fi

log "No plaintext secret files/content detected."
