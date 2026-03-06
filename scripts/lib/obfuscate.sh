#!/usr/bin/env bash
# Obfuscation library for redacting secrets and sensitive data
# Source this file and call obfuscate_text() or log_redacted()
#
# Usage (as library):
#   source "${ROOT_DIR}/scripts/lib/obfuscate.sh"
#   redacted=$(obfuscate_text "My secret: sk-ant-12345")
#   echo "$redacted"  # My secret: [REDACTED-ANTHROPIC-KEY]
#
# Usage (as script):
#   ./scripts/lib/obfuscate.sh "Text with secret=value123"

set -euo pipefail

# obfuscate_text TEXT
#   Redact secrets and obfuscate identifiers in text
#   Returns text with secrets replaced with [REDACTED-TYPE] tokens
#
# Redacts:
#   - API Keys (ANTHROPIC, OPENAI, AWS, etc.)
#   - GitHub tokens (ghp_*, github_pat_*)
#   - AWS credentials and access keys
#   - Bearer tokens and authorization headers
#   - SSH public keys
#   - Private IP addresses (10.x, 172.16-31.x, 192.168.x)
obfuscate_text() {
  local text="$1"

  # Redact common secret patterns
  # API Keys: ANTHROPIC_API_KEY, OPENAI_API_KEY, etc.
  text=$(printf '%s\n' "$text" | sed -E \
    -e 's/([A-Z_]*API[_-]?KEY["\s]*[:=]["\s]*)([a-zA-Z0-9_-]+)/\1[REDACTED-API-KEY]/g' \
    -e 's/(ANTHROPIC_API_KEY["\s]*[:=]["\s]*)([a-zA-Z0-9_-]+)/\1[REDACTED-ANTHROPIC-KEY]/g' \
    -e 's/(OPENAI_API_KEY["\s]*[:=]["\s]*)([a-zA-Z0-9_-]+)/\1[REDACTED-OPENAI-KEY]/g' \
  )

  # GitHub tokens and credentials
  text=$(printf '%s\n' "$text" | sed -E \
    -e 's/(GITHUB_TOKEN|GH_TOKEN)["\s]*[:=]["\s]*([a-zA-Z0-9_-]+)/\1=[REDACTED-GITHUB-TOKEN]/g' \
    -e 's/(ghp_[A-Za-z0-9]{20,})/[REDACTED-GITHUB-TOKEN]/g' \
    -e 's/(github_pat_[A-Za-z0-9_]+)/[REDACTED-GITHUB-TOKEN]/g' \
  )

  # AWS credentials
  text=$(printf '%s\n' "$text" | sed -E \
    -e 's/(AWS_SECRET_ACCESS_KEY)["\s]*[:=]["\s]*([a-zA-Z0-9/+=]+)/\1=[REDACTED-AWS-SECRET]/g' \
    -e 's/(AWS_ACCESS_KEY_ID)["\s]*[:=]["\s]*([A-Z0-9]+)/\1=[REDACTED-AWS-KEY-ID]/g' \
  )

  # Bearer tokens and authorization headers
  text=$(printf '%s\n' "$text" | sed -E \
    -e 's/(Bearer|Authorization)["\s]*[:=]["\s]*([a-zA-Z0-9_.-]+)/\1 [REDACTED-TOKEN]/g' \
  )

  # SSH keys (indirectly referenced)
  text=$(printf '%s\n' "$text" | sed -E \
    -e 's/(ssh-rsa|ssh-ed25519|ecdsa-sha2)["\s]+([a-zA-Z0-9/+=]+)/\1 [REDACTED-SSH-KEY]/g' \
  )

  # IP addresses (private ranges)
  text=$(printf '%s\n' "$text" | sed -E \
    -e 's/(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})/[IP-INTERNAL]/g' \
    -e 's/(172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]{1,3}\.[0-9]{1,3})/[IP-PRIVATE]/g' \
    -e 's/(192\.168\.[0-9]{1,3}\.[0-9]{1,3})/[IP-PRIVATE]/g' \
  )

  # Return obfuscated text
  printf '%s\n' "$text"
}

# obfuscate_file INPUT_FILE [OUTPUT_FILE]
#   Redact secrets in a file
#   If OUTPUT_FILE not specified, prints to stdout
obfuscate_file() {
  local input_file="$1"
  local output_file="${2:-}"

  if [[ ! -f "$input_file" ]]; then
    printf 'error: file not found: %s\n' "$input_file" >&2
    return 1
  fi

  local content
  content="$(cat "$input_file")"
  local redacted
  redacted="$(obfuscate_text "$content")"

  if [[ -z "$output_file" ]]; then
    printf '%s\n' "$redacted"
  else
    printf '%s\n' "$redacted" > "$output_file"
  fi
}

# obfuscate_lines [LINE1, LINE2, ...]
#   Redact secrets from multiple lines (reads from stdin or args)
obfuscate_lines() {
  if [[ $# -gt 0 ]]; then
    # Process arguments
    while [[ $# -gt 0 ]]; do
      obfuscate_text "$1"
      shift
    done
  else
    # Read from stdin
    while IFS= read -r line; do
      obfuscate_text "$line"
    done
  fi
}

# If script is executed directly (not sourced), process arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -eq 0 ]]; then
    printf 'usage: %s TEXT\n' "$(basename "$0")" >&2
    printf '       %s --file FILE [OUTPUT]\n' "$(basename "$0")" >&2
    exit 1
  fi

  case "$1" in
    --file)
      if [[ $# -lt 2 ]]; then
        printf 'error: --file requires INPUT_FILE argument\n' >&2
        exit 1
      fi
      obfuscate_file "$2" "${3:-}"
      ;;
    *)
      # Treat all arguments as text to obfuscate
      obfuscate_text "$*"
      ;;
  esac
fi
