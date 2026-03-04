#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="secrets"

ENC_FILE="${ROOT_DIR}/secrets/bootstrap.env.sops"
OUT_DIR="${HOME}/.config/dev-bootstrap"
OUT_FILE="${OUT_DIR}/secrets.env"
KEY_FILE="${SOPS_AGE_KEY_FILE:-${HOME}/.config/sops/age/keys.txt}"
HOOKS_DIR="${ROOT_DIR}/.githooks"

decrypt_secrets() {
  if [[ ! -f "${ENC_FILE}" ]]; then
    log_skip "no encrypted secrets file at secrets/bootstrap.env.sops"
    return 0
  fi

  if ! has_cmd sops; then
    log_err "sops is required to decrypt secrets"
    return 1
  fi

  if [[ ! -f "${KEY_FILE}" ]]; then
    log_err "missing age key file: ${KEY_FILE}"
    log "create/import your age key, then rerun bootstrap"
    return 1
  fi

  mkdir -p "${OUT_DIR}"
  local tmp
  tmp="$(mktemp "${OUT_FILE}.tmp.XXXXXX")"
  if ! sops --decrypt "${ENC_FILE}" > "${tmp}"; then
    rm -f "${tmp}"
    return 1
  fi
  chmod 600 "${tmp}"
  mv "${tmp}" "${OUT_FILE}"

  log_ok "decrypted secrets to ${OUT_FILE}"
}

install_hygiene_hook() {
  mkdir -p "${HOOKS_DIR}"

  cat > "${HOOKS_DIR}/pre-commit" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"${ROOT_DIR}/scripts/secrets/check-no-plaintext.sh"
if command -v pj >/dev/null 2>&1; then
  if ! pj secret scan --staged; then
    echo "warning: pj secret scan flagged potential issues (see above)" >&2
    echo "         the primary check (check-no-plaintext.sh) passed — continuing" >&2
  fi
fi
HOOK

  chmod +x "${HOOKS_DIR}/pre-commit"
  git -C "${ROOT_DIR}" config core.hooksPath .githooks

  log_ok "installed pre-commit hook at ${HOOKS_DIR}/pre-commit"
}

main() {
  decrypt_secrets
  install_hygiene_hook
}

main "$@"
