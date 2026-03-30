#!/usr/bin/env bash
# 1Password helpers for dotfiles bootstrap scripts.
# Source this file after log.sh and cmd.sh.
#
# Usage:
#   source "${ROOT_DIR}/scripts/lib/log.sh"
#   source "${ROOT_DIR}/scripts/lib/cmd.sh"
#   source "${ROOT_DIR}/scripts/lib/onepassword.sh"
#   TAG="my-script"
#
# Functions:
#   op_restore_file ITEM_NAME OUTPUT_FILE   — restore a Secure Note to a file
#   op_save_file ITEM_NAME INPUT_FILE       — save a file as a Secure Note

# 1Password item name for the age encryption key
export OP_AGE_KEY_ITEM="age-key-dotfiles"

# op_restore_file ITEM_NAME OUTPUT_FILE
#   Restore a Secure Note's notesPlain field to a file (atomic, chmod 600).
#   Requires: op CLI, interactive terminal.
#   Returns 0 on success, 1 on failure.
op_restore_file() {
  local item="$1" output="$2"

  if ! has_cmd op; then
    log_warn "op CLI not available; cannot restore from 1Password"
    return 1
  fi

  if [[ ! -t 0 ]]; then
    log_warn "1Password restore requires an interactive terminal"
    return 1
  fi

  local tmp
  tmp="$(mktemp "${output}.tmp.XXXXXX")"

  if ! op item get "${item}" --fields notesPlain > "${tmp}" 2>/dev/null; then
    rm -f "${tmp}"
    return 1
  fi

  chmod 600 "${tmp}"
  mv "${tmp}" "${output}"
  return 0
}

# op_save_file ITEM_NAME INPUT_FILE
#   Save a file's contents as a Secure Note in 1Password.
#   Requires: op CLI, interactive terminal.
#   Returns 0 on success, 1 on failure.
op_save_file() {
  local item="$1" input="$2"

  if ! has_cmd op; then
    log_warn "op CLI not available; cannot save to 1Password"
    return 1
  fi

  if [[ ! -t 0 ]]; then
    log_warn "1Password save requires an interactive terminal"
    return 1
  fi

  if op item create \
    --category "Secure Note" \
    --title "${item}" \
    "notesPlain=$(cat "${input}")" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}
