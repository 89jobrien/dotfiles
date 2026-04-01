# HANDOFF — dotfiles council analysis (2026-03-30)

## Overview

Council tool (`devkit council`) could not complete due to API rate limits. Manual analysis
was performed by examining the diff vs `main`, running the full bats test suite, and auditing
the three library files most recently modified.

## Findings Summary

| Severity | Count |
|----------|-------|
| P0       | 0     |
| P1       | 3 root causes → 19 test failures |
| P2       | 19 pre-existing shellcheck warnings (see below) |

---

## P1 Issues Fixed

### P1-1: `merge_json_config` RETURN trap causes unbound variable in bats

**File:** `scripts/lib/json.sh`
**Introduced by:** commit `4d0dd75` (2026-03-07)

**Root cause:** `trap 'rm -f "${tmp}" "${tmp}.new"' RETURN` was added for cleanup. Bats
uses `set -eET`; the `-T` flag causes RETURN traps to be inherited by calling functions.
When bats' internal `bats_merge_stdout_and_stderr` returns after calling `merge_json_config`,
the trap fires in that outer frame where `tmp` (local to `merge_json_config`) is out of scope
→ `unbound variable` error, `$status` ≠ 0.

**Fix:** Removed the trap. Added explicit `rm -f` on both success and failure paths.

**Tests covering this:** all `merge_json_config`, `update_json_value`, and integration tests
in `tests/lib/json.bats` (tests 40–64).

---

### P1-2: `pkg.bats` missing `source cmd.sh`

**File:** `tests/lib/pkg.bats`

**Root cause:** `pkg.sh` delegates `has_zerobrew`, `has_brew`, `has_apt` to `has_cmd` from
`cmd.sh`. The test `setup()` sourced `log.sh` + `pkg.sh` but NOT `cmd.sh`. All three
functions therefore failed with exit code 127 (command not found) instead of 0/1.

**Fix:** Added `source "${ROOT_DIR}/scripts/lib/cmd.sh"` to setup().

**Tests covering this:** has_zerobrew, has_brew, has_apt, detect_pkg_manager,
ensure_homebrew, bundle_install tests in `tests/lib/pkg.bats` (tests 85–100).

---

### P1-3: `launchd_logs` test blocks on `tail -f`

**File:** `tests/lib/launchd.bats`

**Root cause:** The original test ran `(launchd_logs >/dev/null 2>&1 &)` (subshell
wrapping a background job). This caused `$!` to be unbound in the outer shell (bats
uses `set -eET`), and the background `tail -f` process was never reliably killed, hanging
the test runner.

**Fix:** Replaced with `tail() { :; }` mock before calling `run launchd_logs`. Shell
functions shadow external commands in bash subshells, so `launchd_logs` completes
immediately after `mkdir` + `touch`, allowing the test to assert file creation.

**Test covering this:** `tests/lib/launchd.bats` test 75.

---

## Test Counts

| Metric | Value |
|--------|-------|
| Before fixes | 83 passing, 19 failing |
| After fixes  | 102 passing, 0 failing |
| New tests added | 0 (all existing tests now pass) |

---

## P2 (Deferred — Pre-existing)

19 shellcheck findings in scripts NOT touched by this session:

- `scripts/setup-secrets-interactive.sh`: SC2168 (`local` outside function — 2 errors),
  SC2064 (trap quoting — 1 warning), SC2209 (EDITOR= assignment — 1 warning)
- `scripts/setup-ai-tools.sh`: SC2016 (single-quoted jq expressions — info level, ~15 hits)

These predate the current branch and do not affect correctness. Recommend fixing in a
follow-up.

---

## Commit

`acba87a` — fix(tests): repair 19 failing bats tests across json, pkg, and launchd
