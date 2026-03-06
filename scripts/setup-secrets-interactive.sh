#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="secrets-setup"

SECRETS_DIR="${HOME}/.config/dev-bootstrap"
SECRETS_FILE="${SECRETS_DIR}/secrets.env"
AGE_KEY_FILE="${HOME}/.config/sops/age/keys.txt"
TEMP_SECRETS=$(mktemp)

# Cleanup temp file on exit
trap "rm -f ${TEMP_SECRETS}" EXIT

# Check prerequisites
if [[ ! -f "${AGE_KEY_FILE}" ]]; then
  log_err "age key not found at ${AGE_KEY_FILE}"
  log "Set up age key first: https://github.com/FiloSottile/age"
  exit 1
fi

if ! command -v sops >/dev/null 2>&1; then
  log_err "sops not installed"
  log "Install via: brew install sops"
  exit 1
fi

mkdir -p "${SECRETS_DIR}"

# Define secrets to prompt for
declare -A SECRETS=(
  [ANTHROPIC_API_KEY]="Anthropic API key (https://console.anthropic.com)"
  [OPENAI_API_KEY]="OpenAI API key (https://platform.openai.com/api-keys)"
  [GITHUB_TOKEN]="GitHub personal access token (https://github.com/settings/tokens)"
  [AWS_ACCESS_KEY_ID]="AWS access key ID (optional, leave blank to skip)"
  [AWS_SECRET_ACCESS_KEY]="AWS secret access key (optional, leave blank to skip)"
)

log "Interactive Secrets Setup"
log "========================"
log ""
log "Enter values for each secret. Leave blank to skip optional ones."
log "Values will be encrypted and stored at: ${SECRETS_FILE}"
log ""

# Prompt for each secret
for key in "${!SECRETS[@]}"; do
  local prompt="${SECRETS[$key]}"
  local value=""

  # Handle optional vs required
  if [[ "$key" == AWS* ]]; then
    printf "%s [optional]: " "$prompt"
  else
    printf "%s: " "$prompt"
  fi

  # Read input without echoing (for security)
  if [[ -t 0 ]]; then
    read -rs value
    printf "\n"
  else
    read -r value
  fi

  # Only add to temp file if value is provided
  if [[ -n "$value" ]]; then
    echo "export ${key}='${value}'" >> "${TEMP_SECRETS}"
  fi
done

log ""
if [[ ! -s "${TEMP_SECRETS}" ]]; then
  log_warn "no secrets provided"
  exit 0
fi

# Show summary
log "Provided secrets:"
grep -o "^export [A-Z_]*" "${TEMP_SECRETS}" | sed 's/export /  /' || true
log ""

# Encrypt with sops
log "Encrypting secrets..."
EDITOR=cat sops "${SECRETS_FILE}" 2>/dev/null || true

# Copy secrets to encrypted file
cp "${TEMP_SECRETS}" "${SECRETS_FILE}"

# Encrypt in place
SOPS_AGE_KEY_FILE="${AGE_KEY_FILE}" sops -e -i "${SECRETS_FILE}"

chmod 600 "${SECRETS_FILE}"
log_ok "secrets encrypted and saved to ${SECRETS_FILE}"
log ""
log "To decrypt and use: source ${SECRETS_FILE} (auto-loaded in ~/.zshrc)"
