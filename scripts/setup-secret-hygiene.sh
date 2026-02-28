#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${ROOT_DIR}/.githooks"

log() {
  printf '[secret-hygiene] %s\n' "$*"
}

mkdir -p "${HOOKS_DIR}"

cat > "${HOOKS_DIR}/pre-commit" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"${ROOT_DIR}/scripts/secrets/check-no-plaintext.sh"
if command -v pj >/dev/null 2>&1; then
  pj secret scan --staged
fi
HOOK

chmod +x "${HOOKS_DIR}/pre-commit"

git -C "${ROOT_DIR}" config core.hooksPath .githooks

log "Installed local dotfiles pre-commit hook at ${HOOKS_DIR}/pre-commit"
log "Policy: no plaintext secret files/content; optional pj staged scan."
