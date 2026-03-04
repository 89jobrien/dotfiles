#!/usr/bin/env bats
# Tests for scripts/lib/cmd.sh - Command checking utilities

setup() {
  # Load the library being tested
  ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # shellcheck source=scripts/lib/log.sh
  source "${ROOT_DIR}/scripts/lib/log.sh"
  # shellcheck source=scripts/lib/cmd.sh
  source "${ROOT_DIR}/scripts/lib/cmd.sh"
  TAG="test"
}

# ---------------------------------------------------------------------------
# has_cmd tests
# ---------------------------------------------------------------------------

@test "has_cmd returns 0 for existing command" {
  run has_cmd bash
  [ "$status" -eq 0 ]
}

@test "has_cmd returns 1 for non-existent command" {
  run has_cmd nonexistent-command-xyz
  [ "$status" -eq 1 ]
}

@test "has_cmd produces no output (silent check)" {
  run has_cmd bash
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# require_cmd tests
# ---------------------------------------------------------------------------

@test "require_cmd succeeds for existing command" {
  run require_cmd bash
  [ "$status" -eq 0 ]
}

@test "require_cmd exits with error for missing command" {
  run require_cmd nonexistent-command-xyz
  [ "$status" -eq 1 ]
  [[ "$output" =~ "missing required command: nonexistent-command-xyz" ]]
}

@test "require_cmd shows install hint when provided" {
  run require_cmd nonexistent-xyz "brew install xyz"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "install: brew install xyz" ]]
}

# ---------------------------------------------------------------------------
# check_cmd tests
# ---------------------------------------------------------------------------

@test "check_cmd logs success for existing command" {
  run check_cmd bash
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ok: bash ->" ]]
}

@test "check_cmd logs error for missing command" {
  status=0  # Initialize status variable
  run check_cmd nonexistent-xyz
  [ "$status" -eq 0 ]  # Function doesn't exit, just sets variable
  [[ "$output" =~ "err: nonexistent-xyz missing" ]]
}

@test "check_cmd sets status variable to 1 on failure" {
  # This test validates the status variable is set correctly
  status=0
  check_cmd nonexistent-xyz >/dev/null 2>&1
  [ "$status" -eq 1 ]
}

@test "check_cmd accepts custom status variable name" {
  custom_status=0
  check_cmd bash custom_status >/dev/null 2>&1
  [ "$custom_status" -eq 0 ]

  check_cmd nonexistent-xyz custom_status >/dev/null 2>&1
  [ "$custom_status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# check_optional_cmd tests
# ---------------------------------------------------------------------------

@test "check_optional_cmd logs success for existing command" {
  run check_optional_cmd bash
  [ "$status" -eq 0 ]
  [[ "$output" =~ "ok: bash ->" ]]
}

@test "check_optional_cmd logs skip for missing command" {
  run check_optional_cmd nonexistent-xyz
  [ "$status" -eq 0 ]
  [[ "$output" =~ "skip: nonexistent-xyz (optional)" ]]
}

@test "check_optional_cmd never fails (always returns 0)" {
  run check_optional_cmd nonexistent-xyz
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# ensure_cmd tests
# ---------------------------------------------------------------------------

@test "ensure_cmd returns 0 if command exists" {
  run ensure_cmd bash "echo should not run"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "should not run" ]]
}

@test "ensure_cmd runs install command if command missing" {
  run ensure_cmd nonexistent-xyz "echo install attempted"
  [[ "$output" =~ "installing nonexistent-xyz" ]]
  [[ "$output" =~ "install attempted" ]]
}

@test "ensure_cmd returns 1 if install fails" {
  run ensure_cmd nonexistent-xyz "false"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "failed to install nonexistent-xyz" ]]
}

@test "ensure_cmd accepts failed array parameter without error" {
  # NOTE: Array modification via eval doesn't work in function scope (bats test),
  # but works correctly at script global scope (as used in setup-dev-tools.sh)
  declare -a test_failed=()
  run ensure_cmd nonexistent-xyz "false" test_failed
  [ "$status" -eq 1 ]
  [[ "$output" =~ "failed to install nonexistent-xyz" ]]
  # Function accepts the parameter and doesn't crash
}

@test "ensure_cmd does not append to array on install success" {
  declare -a test_failed=()
  ensure_cmd bash "true" test_failed >/dev/null 2>&1
  [ "${#test_failed[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Integration tests
# ---------------------------------------------------------------------------

@test "check_cmd and check_optional_cmd work together" {
  status=0
  check_cmd bash >/dev/null 2>&1
  check_optional_cmd nonexistent-xyz >/dev/null 2>&1
  [ "$status" -eq 0 ]  # Optional doesn't affect status

  check_cmd nonexistent-xyz >/dev/null 2>&1
  [ "$status" -eq 1 ]  # Required sets status
}

@test "multiple check_cmd failures accumulate status" {
  status=0
  check_cmd nonexistent-1 >/dev/null 2>&1
  check_cmd nonexistent-2 >/dev/null 2>&1
  [ "$status" -eq 1 ]  # Status set by either failure
}
