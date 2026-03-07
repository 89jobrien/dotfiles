#!/usr/bin/env bash
# JSON configuration manipulation utilities for dotfiles scripts.
# Requires jq to be installed.
# Source this file after log.sh and cmd.sh.
#
# Usage:
#   source "${ROOT_DIR}/scripts/lib/log.sh"
#   source "${ROOT_DIR}/scripts/lib/cmd.sh"
#   source "${ROOT_DIR}/scripts/lib/json.sh"
#   TAG="my-script"
#
#   merge_json_config FILE JQ_FILTER [jq_args...]
#   read_json_value FILE JQ_PATH
#   update_json_value FILE JQ_PATH VALUE
#   validate_json FILE

# merge_json_config FILE JQ_FILTER [jq_args...]
#   Read FILE (or start from {}), apply JQ_FILTER, write back atomically.
#   Example:
#     merge_json_config config.json '.foo = "bar"'
#     merge_json_config config.json '.servers.personal = {command: $cmd}' --arg cmd "myserver"
merge_json_config() {
  local cfg="$1" filter="$2"
  shift 2

  # Ensure jq is available
  require_cmd jq

  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "${tmp}" "${tmp}.new"' RETURN

  # Start from existing config or empty object
  if [[ -f "${cfg}" ]]; then
    cp "${cfg}" "${tmp}"
  else
    printf '{}' > "${tmp}"
  fi

  # Apply jq filter and write atomically
  if ! jq "$@" "${filter}" "${tmp}" > "${tmp}.new"; then
    log_err "jq filter failed for ${cfg}"
    return 1
  fi

  mv "${tmp}.new" "${cfg}"
  return 0
}

# read_json_value FILE JQ_PATH
#   Read a value from JSON file using jq path.
#   Example: read_json_value config.json '.servers.personal.command'
read_json_value() {
  local cfg="$1" path="$2"

  if [[ ! -f "${cfg}" ]]; then
    log_err "JSON file not found: ${cfg}"
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    log_err "jq is required for JSON manipulation"
    return 1
  fi

  jq -r "${path}" "${cfg}"
}

# update_json_value FILE JQ_PATH VALUE
#   Update a single value in JSON file.
#   Example: update_json_value config.json '.theme' 'dark'
update_json_value() {
  local cfg="$1" path="$2" value="$3"
  merge_json_config "${cfg}" "${path} = \$val" --arg val "${value}"
}

# validate_json FILE
#   Validate that FILE contains valid JSON.
#   Returns 0 if valid, 1 if invalid.
validate_json() {
  local cfg="$1"

  if [[ ! -f "${cfg}" ]]; then
    log_err "JSON file not found: ${cfg}"
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    log_err "jq is required for JSON validation"
    return 1
  fi

  if jq empty "${cfg}" >/dev/null 2>&1; then
    return 0
  else
    log_err "invalid JSON in ${cfg}"
    return 1
  fi
}

# ensure_json_dir FILE
#   Ensure the parent directory of FILE exists.
ensure_json_dir() {
  local cfg="$1"
  local dir
  dir="$(dirname "${cfg}")"
  mkdir -p "${dir}"
}
