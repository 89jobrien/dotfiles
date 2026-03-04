#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="sops-env"

INPUT_FILE="${1:-${ROOT_DIR}/secrets/.env.json}"
OUTPUT_FILE="${2:-${ROOT_DIR}/secrets/.env.sops.json}"
KEY_FILE="${SOPS_AGE_KEY_FILE:-${MISE_SOPS_AGE_KEY_FILE:-${HOME}/.config/sops/age/keys.txt}}"

require_cmd sops

if [[ ! -f "${INPUT_FILE}" ]]; then
  log "Input JSON not found: ${INPUT_FILE}"
  log "Create it first (gitignored), e.g. secrets/.env.json"
  exit 1
fi

require_cmd jq

jq empty "${INPUT_FILE}" >/dev/null

if [[ ! -f "${KEY_FILE}" ]]; then
  log "Age key file not found: ${KEY_FILE}"
  log "Generate one with: age-keygen -o ~/.config/sops/age/keys.txt"
  exit 1
fi

recipient="$(grep '^# public key:' "${KEY_FILE}" | awk '{print $4}' | head -n1 || true)"
if [[ -z "${recipient}" ]]; then
  log "Could not extract age recipient from ${KEY_FILE}"
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_FILE}")"
tmp="$(mktemp "${OUTPUT_FILE}.tmp.XXXXXX")"
if ! sops encrypt --input-type json --output-type json --age "${recipient}" "${INPUT_FILE}" > "${tmp}"; then
  rm -f "${tmp}"
  exit 1
fi
mv "${tmp}" "${OUTPUT_FILE}"

log "Wrote encrypted env JSON: ${OUTPUT_FILE}"
