#!/usr/bin/env bats
# Tests for scripts/lib/pkg.sh - Package manager detection utilities

setup() {
  ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${ROOT_DIR}/scripts/lib/log.sh"
  source "${ROOT_DIR}/scripts/lib/cmd.sh"
  source "${ROOT_DIR}/scripts/lib/pkg.sh"
  TAG="test"
}

# has_zerobrew tests

@test "has_zerobrew: returns 0 when zb command exists" {
  if command -v zb >/dev/null 2>&1; then
    run has_zerobrew
    [ "$status" -eq 0 ]
  else
    skip "zb not installed on this system"
  fi
}

@test "has_zerobrew: returns 1 when zb command missing" {
  # Only test if zb is actually missing
  if ! command -v zb >/dev/null 2>&1; then
    run has_zerobrew
    [ "$status" -eq 1 ]
  else
    skip "zb is installed on this system"
  fi
}

# has_brew tests

@test "has_brew: returns 0 when brew command exists" {
  if command -v brew >/dev/null 2>&1; then
    run has_brew
    [ "$status" -eq 0 ]
  else
    skip "brew not installed on this system"
  fi
}

@test "has_brew: returns 1 when brew command missing" {
  # Only test if brew is actually missing
  if ! command -v brew >/dev/null 2>&1; then
    run has_brew
    [ "$status" -eq 1 ]
  else
    skip "brew is installed on this system"
  fi
}

# has_apt tests

@test "has_apt: returns 0 when apt command exists" {
  if command -v apt >/dev/null 2>&1; then
    run has_apt
    [ "$status" -eq 0 ]
  else
    skip "apt not installed on this system"
  fi
}

@test "has_apt: returns 1 when apt command missing" {
  # Only test if apt is actually missing
  if ! command -v apt >/dev/null 2>&1; then
    run has_apt
    [ "$status" -eq 1 ]
  else
    skip "apt is installed on this system"
  fi
}

# detect_pkg_manager tests

@test "detect_pkg_manager: returns zerobrew when zb exists" {
  if command -v zb >/dev/null 2>&1; then
    run detect_pkg_manager
    [ "$status" -eq 0 ]
    [ "$output" = "zerobrew" ]
  else
    skip "zb not installed on this system"
  fi
}

@test "detect_pkg_manager: returns homebrew when only brew exists" {
  if command -v brew >/dev/null 2>&1 && ! command -v zb >/dev/null 2>&1; then
    run detect_pkg_manager
    [ "$status" -eq 0 ]
    [ "$output" = "homebrew" ]
  else
    skip "brew not installed or zb is installed (takes priority)"
  fi
}

@test "detect_pkg_manager: returns apt when only apt exists" {
  if command -v apt >/dev/null 2>&1 && ! command -v brew >/dev/null 2>&1 && ! command -v zb >/dev/null 2>&1; then
    run detect_pkg_manager
    [ "$status" -eq 0 ]
    [ "$output" = "apt" ]
  else
    skip "apt not installed or brew/zb is installed (takes priority)"
  fi
}

@test "detect_pkg_manager: returns empty when no package manager" {
  # Can't easily test without mocking, skip if any package manager exists
  if command -v zb >/dev/null 2>&1 || command -v brew >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
    skip "package manager installed on this system"
  else
    run detect_pkg_manager
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
  fi
}

@test "detect_pkg_manager: respects priority order zb > brew > apt" {
  # This test documents the priority order
  local result
  result="$(detect_pkg_manager)"

  if [ "$result" = "zerobrew" ]; then
    # If zerobrew detected, zb must exist
    command -v zb >/dev/null 2>&1
    [ $? -eq 0 ]
  elif [ "$result" = "homebrew" ]; then
    # If homebrew detected, brew must exist and zb must not
    command -v brew >/dev/null 2>&1
    [ $? -eq 0 ]
    ! command -v zb >/dev/null 2>&1
    [ $? -eq 0 ]
  elif [ "$result" = "apt" ]; then
    # If apt detected, apt must exist and brew/zb must not
    command -v apt >/dev/null 2>&1
    [ $? -eq 0 ]
    ! command -v brew >/dev/null 2>&1
    [ $? -eq 0 ]
    ! command -v zb >/dev/null 2>&1
    [ $? -eq 0 ]
  fi
}

# ensure_homebrew tests

@test "ensure_homebrew: succeeds when zerobrew exists" {
  if command -v zb >/dev/null 2>&1; then
    run ensure_homebrew
    [ "$status" -eq 0 ]
  else
    skip "zb not installed on this system"
  fi
}

@test "ensure_homebrew: succeeds when brew exists" {
  if command -v brew >/dev/null 2>&1; then
    run ensure_homebrew
    [ "$status" -eq 0 ]
  else
    skip "brew not installed on this system"
  fi
}

@test "ensure_homebrew: fails when neither zb nor brew exist" {
  if ! command -v zb >/dev/null 2>&1 && ! command -v brew >/dev/null 2>&1; then
    run ensure_homebrew
    [ "$status" -eq 1 ]
    [[ "$output" =~ "neither zerobrew nor Homebrew found" ]]
  else
    skip "zb or brew is installed on this system"
  fi
}

# bundle_install tests

@test "bundle_install: fails when Brewfile missing" {
  run bundle_install "/nonexistent/Brewfile"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Brewfile not found" ]]
}

@test "bundle_install: uses zerobrew when available" {
  if ! command -v zb >/dev/null 2>&1; then
    skip "zb not installed on this system"
  fi

  # Create a temporary empty Brewfile
  local tmpfile
  tmpfile="$(mktemp)"
  echo "# test brewfile" > "$tmpfile"

  run bundle_install "$tmpfile"
  rm -f "$tmpfile"

  # Should attempt to use zerobrew
  [[ "$output" =~ "zerobrew" ]]
}

@test "bundle_install: uses brew when zb unavailable" {
  if ! command -v brew >/dev/null 2>&1 || command -v zb >/dev/null 2>&1; then
    skip "brew not installed or zb is installed (takes priority)"
  fi

  # Create a temporary empty Brewfile
  local tmpfile
  tmpfile="$(mktemp)"
  echo "# test brewfile" > "$tmpfile"

  run bundle_install "$tmpfile"
  rm -f "$tmpfile"

  # Should attempt to use brew
  [[ "$output" =~ "brew bundle" ]]
}

@test "bundle_install: fails when no package manager available" {
  if command -v zb >/dev/null 2>&1 || command -v brew >/dev/null 2>&1; then
    skip "package manager installed on this system"
  fi

  local tmpfile
  tmpfile="$(mktemp)"
  echo "# test brewfile" > "$tmpfile"

  run bundle_install "$tmpfile"
  rm -f "$tmpfile"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "no package manager found" ]]
}
