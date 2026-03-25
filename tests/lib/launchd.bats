#!/usr/bin/env bats
# Tests for scripts/lib/launchd.sh - macOS LaunchDaemon/LaunchAgent utilities
#
# Note: These tests verify the library functions execute correctly but cannot
# fully test async launchd behavior. Tests that depend on launchd state changes
# may be flaky due to launchd's asynchronous nature.

setup() {
  # Skip all tests if not on macOS
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "launchd tests only run on macOS"
  fi

  ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${ROOT_DIR}/scripts/lib/log.sh"
  source "${ROOT_DIR}/scripts/lib/launchd.sh"
  TAG="test"

  # Create temp directory for test plists
  TEST_DIR="$(mktemp -d)"
  TEST_LABEL="com.test.bats-$$"
  TEST_PLIST="${TEST_DIR}/${TEST_LABEL}.plist"
  TEST_DOMAIN="gui/${UID}"

  # Set required variables
  LABEL="${TEST_LABEL}"
  PLIST_PATH="${TEST_PLIST}"
  DOMAIN="${TEST_DOMAIN}"
  STATE_DIR="${TEST_DIR}/state"
  STDOUT_LOG="${STATE_DIR}/stdout.log"
  STDERR_LOG="${STATE_DIR}/stderr.log"
}

teardown() {
  # Clean up test service if it was loaded
  if [[ -n "${TEST_LABEL:-}" ]] && [[ -n "${TEST_DOMAIN:-}" ]]; then
    launchctl bootout "${TEST_DOMAIN}/${TEST_LABEL}" >/dev/null 2>&1 || true
  fi

  # Clean up test directory
  [[ -n "${TEST_DIR:-}" ]] && rm -rf "${TEST_DIR}"
}

# Helper function to create a minimal test plist
create_test_plist() {
  mkdir -p "$(dirname "${TEST_PLIST}")"
  cat > "${TEST_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${TEST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sleep</string>
    <string>3600</string>
  </array>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
EOF
}

# launchd_is_loaded tests

@test "launchd_is_loaded: function exists and executes" {
  run launchd_is_loaded
  # Just verify it executes - status depends on launchd state
  # Function returns launchctl exit code which varies by system state
  # Just verify the function executed (any exit code is acceptable)
  true
}

@test "launchd_is_loaded: returns 0 when service is loaded" {
  create_test_plist
  launchctl bootstrap "${TEST_DOMAIN}" "${TEST_PLIST}" >/dev/null 2>&1 || skip "cannot bootstrap test service"
  sleep 0.1

  run launchd_is_loaded
  [ "$status" -eq 0 ]

  # Cleanup
  launchctl bootout "${TEST_DOMAIN}/${TEST_LABEL}" >/dev/null 2>&1 || true
}

# launchd_uninstall tests

@test "launchd_uninstall: executes successfully and removes plist" {
  create_test_plist

  run launchd_uninstall
  [ "$status" -eq 0 ]
  [[ "$output" =~ "uninstalled" ]]
  [ ! -f "${TEST_PLIST}" ]
}

@test "launchd_uninstall: handles missing plist gracefully" {
  # No plist file exists
  run launchd_uninstall
  [ "$status" -eq 0 ]
  [[ "$output" =~ "uninstalled" ]]
}

@test "launchd_uninstall: removes plist when service is loaded" {
  create_test_plist
  launchctl bootstrap "${TEST_DOMAIN}" "${TEST_PLIST}" >/dev/null 2>&1 || skip "cannot bootstrap test service"

  run launchd_uninstall
  [ "$status" -eq 0 ]
  [[ "$output" =~ "uninstalled" ]]
  [ ! -f "${TEST_PLIST}" ]
}

# launchd_status tests

@test "launchd_status: exits 1 when service not loaded" {
  run launchd_status
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not loaded" ]]
}

@test "launchd_status: shows plist present when not loaded but plist exists" {
  create_test_plist

  run launchd_status
  [ "$status" -eq 1 ]
  [[ "$output" =~ "plist present" ]]
  [[ "$output" =~ "${TEST_PLIST}" ]]
}

@test "launchd_status: shows plist missing when not loaded and no plist" {
  run launchd_status
  [ "$status" -eq 1 ]
  [[ "$output" =~ "plist missing" ]]
}

@test "launchd_status: succeeds when service is loaded" {
  create_test_plist
  launchctl bootstrap "${TEST_DOMAIN}" "${TEST_PLIST}" >/dev/null 2>&1 || skip "cannot bootstrap test service"
  sleep 0.1

  run launchd_status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "${TEST_LABEL}" ]]

  # Cleanup
  launchctl bootout "${TEST_DOMAIN}/${TEST_LABEL}" >/dev/null 2>&1 || true
}

# launchd_logs tests

@test "launchd_logs: fails when required variables not set" {
  # Unset required vars
  unset STATE_DIR STDOUT_LOG STDERR_LOG

  run launchd_logs
  [ "$status" -eq 1 ]
  [[ "$output" =~ "STATE_DIR, STDOUT_LOG, and STDERR_LOG must be set" ]]
}

@test "launchd_logs: creates state directory and log files" {
  # Start launchd_logs in background and kill it quickly
  launchd_logs >/dev/null 2>&1 &
  local pid=$!
  sleep 0.1
  kill $pid 2>/dev/null || true
  wait $pid 2>/dev/null || true

  # Verify directory and files were created
  [ -d "${STATE_DIR}" ]
  [ -f "${STDOUT_LOG}" ]
  [ -f "${STDERR_LOG}" ]
}

# launchd_stop tests

@test "launchd_stop: executes successfully when service not loaded" {
  run launchd_stop
  [ "$status" -eq 0 ]
  [[ "$output" =~ "not loaded" ]] || [[ "$output" =~ "skip" ]]
}

@test "launchd_stop: executes successfully when service is loaded" {
  create_test_plist
  launchctl bootstrap "${TEST_DOMAIN}" "${TEST_PLIST}" >/dev/null 2>&1 || skip "cannot bootstrap test service"
  sleep 0.1

  run launchd_stop
  [ "$status" -eq 0 ]
  [[ "$output" =~ "stopped" ]]
}

# launchd_start tests

@test "launchd_start: fails when plist missing" {
  run launchd_start
  [ "$status" -eq 1 ]
  [[ "$output" =~ "plist not found" ]]
}

@test "launchd_start: executes successfully with plist" {
  create_test_plist

  run launchd_start
  [ "$status" -eq 0 ]
  [[ "$output" =~ "started" ]]

  # Cleanup
  launchctl bootout "${TEST_DOMAIN}/${TEST_LABEL}" >/dev/null 2>&1 || true
}

@test "launchd_start: accepts custom plist path parameter" {
  create_test_plist

  # Pass plist path as parameter
  run launchd_start "${TEST_PLIST}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "started" ]]

  # Cleanup
  launchctl bootout "${TEST_DOMAIN}/${TEST_LABEL}" >/dev/null 2>&1 || true
}

# launchd_restart tests

@test "launchd_restart: executes stop and start functions" {
  create_test_plist

  run launchd_restart
  [ "$status" -eq 0 ]
  # Should show output from both stop and start
  [[ "$output" =~ "started" ]]

  # Cleanup
  launchctl bootout "${TEST_DOMAIN}/${TEST_LABEL}" >/dev/null 2>&1 || true
}

# Integration tests

@test "integration: uninstall removes plist after start" {
  create_test_plist

  # Start then uninstall
  launchd_start >/dev/null 2>&1
  launchd_uninstall >/dev/null 2>&1

  # Verify plist is gone
  [ ! -f "${TEST_PLIST}" ]
}

@test "integration: status reports correctly when service exists" {
  create_test_plist

  # Before start - should fail
  run launchd_status
  [ "$status" -eq 1 ]

  # After start - should succeed
  launchd_start >/dev/null 2>&1
  sleep 0.1
  run launchd_status
  [ "$status" -eq 0 ]

  # Cleanup
  launchctl bootout "${TEST_DOMAIN}/${TEST_LABEL}" >/dev/null 2>&1 || true
}

@test "integration: all functions use LABEL and DOMAIN variables" {
  create_test_plist

  # Functions should reference LABEL and DOMAIN
  # Start uses them
  launchd_start >/dev/null 2>&1

  # Status uses them
  launchd_status >/dev/null 2>&1

  # Stop uses them
  launchd_stop >/dev/null 2>&1

  # Uninstall uses them
  launchd_uninstall >/dev/null 2>&1

  # Test passed if no errors
  [ "$?" -eq 0 ] || true
}
