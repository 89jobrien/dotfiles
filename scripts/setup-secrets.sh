#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENC_FILE="${ROOT_DIR}/secrets/bootstrap.env.sops"
OUT_DIR="${HOME}/.config/dev-bootstrap"
OUT_FILE="${OUT_DIR}/secrets.env"
KEY_FILE="${SOPS_AGE_KEY_FILE:-${HOME}/.config/sops/age/keys.txt}"

log() {
  printf '[secrets] %s\n' "$*"
}

if [[ ! -f "${ENC_FILE}" ]]; then
  log "No encrypted secrets file found at secrets/bootstrap.env.sops; skipping."
  exit 0
fi

if ! command -v sops >/dev/null 2>&1; then
  log "sops is required to decrypt secrets."
  exit 1
fi

if [[ ! -f "${KEY_FILE}" ]]; then
  log "Missing age key file: ${KEY_FILE}"
  log "Create/import your age key, then rerun bootstrap."
  exit 1
fi

mkdir -p "${OUT_DIR}"
sops --decrypt "${ENC_FILE}" > "${OUT_FILE}"
chmod 600 "${OUT_FILE}"

log "Decrypted secrets to ${OUT_FILE}"
