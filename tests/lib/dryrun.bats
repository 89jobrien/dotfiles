#!/usr/bin/env bats
# Tests for scripts/lib/dryrun.sh - Dry-run mode handling utilities

setup() {
  ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${ROOT_DIR}/scripts/lib/log.sh"
  source "${ROOT_DIR}/scripts/lib/dryrun.sh"
  TAG="test"

  # Reset dry-run state before each test
  DRY_RUN=0
}

# set_dryrun_mode tests

@test "set_dryrun_mode: enables dry-run when passed 1" {
  set_dryrun_mode 1
  [ "${DRY_RUN}" -eq 1 ]
}

@test "set_dryrun_mode: disables dry-run when passed 0" {
  DRY_RUN=1
  set_dryrun_mode 0
  [ "${DRY_RUN}" -eq 0 ]
}

@test "set_dryrun_mode: defaults to 0 when no argument" {
  DRY_RUN=1
  set_dryrun_mode
  [ "${DRY_RUN}" -eq 0 ]
}

# is_dryrun tests

@test "is_dryrun: returns 0 when dry-run enabled" {
  DRY_RUN=1
  run is_dryrun
  [ "$status" -eq 0 ]
}

@test "is_dryrun: returns 1 when dry-run disabled" {
  DRY_RUN=0
  run is_dryrun
  [ "$status" -eq 1 ]
}

# dryrun_exec tests

@test "dryrun_exec: executes command when dry-run disabled" {
  DRY_RUN=0
  run dryrun_exec echo "test output"
  [ "$status" -eq 0 ]
  [[ "$output" == "test output" ]]
}

@test "dryrun_exec: logs command when dry-run enabled" {
  DRY_RUN=1
  run dryrun_exec echo "test output"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "dry-run" ]]
  [[ "$output" =~ "echo test output" ]]
}

@test "dryrun_exec: does not execute command when dry-run enabled" {
  DRY_RUN=1
  # This would fail if actually executed
  run dryrun_exec false
  [ "$status" -eq 0 ]
  [[ "$output" =~ "dry-run" ]]
  [[ "$output" =~ "false" ]]
}

@test "dryrun_exec: preserves command exit status when dry-run disabled" {
  DRY_RUN=0
  run dryrun_exec false
  [ "$status" -eq 1 ]
}

# parse_dryrun_args tests

@test "parse_dryrun_args: sets DRY_RUN=1 when --dry-run present" {
  parse_dryrun_args --dry-run
  [ "${DRY_RUN}" -eq 1 ]
}

@test "parse_dryrun_args: removes --dry-run from remaining args" {
  parse_dryrun_args arg1 --dry-run arg2
  [ "${#DRYRUN_REMAINING_ARGS[@]}" -eq 2 ]
  [ "${DRYRUN_REMAINING_ARGS[0]}" = "arg1" ]
  [ "${DRYRUN_REMAINING_ARGS[1]}" = "arg2" ]
}

@test "parse_dryrun_args: preserves non-dryrun args" {
  parse_dryrun_args arg1 arg2 arg3
  [ "${#DRYRUN_REMAINING_ARGS[@]}" -eq 3 ]
  [ "${DRYRUN_REMAINING_ARGS[0]}" = "arg1" ]
  [ "${DRYRUN_REMAINING_ARGS[1]}" = "arg2" ]
  [ "${DRYRUN_REMAINING_ARGS[2]}" = "arg3" ]
}

@test "parse_dryrun_args: leaves DRY_RUN=0 when no --dry-run" {
  parse_dryrun_args arg1 arg2
  [ "${DRY_RUN}" -eq 0 ]
}

@test "parse_dryrun_args: handles empty args" {
  parse_dryrun_args
  [ "${DRY_RUN}" -eq 0 ]
  [ "${#DRYRUN_REMAINING_ARGS[@]}" -eq 0 ]
}

# parse_dryrun_flag tests

@test "parse_dryrun_flag: returns 0 for --dry-run" {
  run parse_dryrun_flag --dry-run
  [ "$status" -eq 0 ]
}

@test "parse_dryrun_flag: returns 1 for other flags" {
  run parse_dryrun_flag --help
  [ "$status" -eq 1 ]
}

@test "parse_dryrun_flag: returns 1 for non-flags" {
  run parse_dryrun_flag arg1
  [ "$status" -eq 1 ]
}

# Integration tests

@test "integration: full workflow with parse and exec" {
  parse_dryrun_args --dry-run command arg1
  set -- "${DRYRUN_REMAINING_ARGS[@]}"

  [ "${DRY_RUN}" -eq 1 ]
  [ "$#" -eq 2 ]
  [ "$1" = "command" ]
  [ "$2" = "arg1" ]

  run dryrun_exec echo "would execute"
  [[ "$output" =~ "dry-run" ]]
}

@test "integration: respects DRY_RUN environment variable" {
  export DRY_RUN=1
  source "${ROOT_DIR}/scripts/lib/dryrun.sh"

  run dryrun_exec echo "test"
  [[ "$output" =~ "dry-run" ]]
}
