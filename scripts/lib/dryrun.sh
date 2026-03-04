#!/usr/bin/env bash
# Dry-run mode handling for dotfiles scripts.
# Source this file after log.sh.
#
# Usage:
#   source "${ROOT_DIR}/scripts/lib/log.sh"
#   source "${ROOT_DIR}/scripts/lib/dryrun.sh"
#   TAG="my-script"
#
#   parse_dryrun_args "$@"         # parse --dry-run flag, sets DRY_RUN var
#   set_dryrun_mode 1              # manually enable dry-run mode
#   is_dryrun                      # returns 0 if dry-run enabled
#   dryrun_exec command args...    # execute command (or log if dry-run)

# Global dry-run state (0 = disabled, 1 = enabled)
DRY_RUN="${DRY_RUN:-0}"

# set_dryrun_mode MODE
#   Manually set dry-run mode (0 or 1)
set_dryrun_mode() {
  DRY_RUN="${1:-0}"
}

# is_dryrun
#   Returns 0 if dry-run mode is enabled, 1 otherwise
is_dryrun() {
  [[ "${DRY_RUN}" -eq 1 ]]
}

# dryrun_exec COMMAND [ARGS...]
#   Execute command if dry-run disabled, or log the command if enabled
dryrun_exec() {
  if is_dryrun; then
    log "[dry-run] $*"
  else
    "$@"
  fi
}

# parse_dryrun_args ARGS...
#   Parse command line arguments for --dry-run flag.
#   Sets DRY_RUN=1 if flag found. Removes flag from positional params.
#   Usage in main script:
#     parse_dryrun_args "$@"
#     set -- "${DRYRUN_REMAINING_ARGS[@]}"
parse_dryrun_args() {
  DRYRUN_REMAINING_ARGS=()
  for arg in "$@"; do
    case "${arg}" in
      --dry-run)
        DRY_RUN=1
        ;;
      *)
        DRYRUN_REMAINING_ARGS+=("${arg}")
        ;;
    esac
  done
}

# Alternative: parse_dryrun_flag ARG
#   Check if a single argument is --dry-run. Returns 0 if match.
#   Use in case statements:
#     case "$1" in
#       --dry-run) set_dryrun_mode 1 ;;
#     esac
parse_dryrun_flag() {
  [[ "$1" == "--dry-run" ]]
}
