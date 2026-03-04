# Dotfiles Tests

Unit tests for shell script libraries and utilities using [Bats](https://github.com/bats-core/bats-core).

## Running Tests

```bash
# Run all tests
mise run test

# Run only library tests
mise run test-lib

# Run specific test file
bats tests/lib/cmd.bats
```

## Test Structure

```text
tests/
├── README.md           # This file
└── lib/                # Tests for scripts/lib/* libraries
    ├── cmd.bats        # Command checking utilities tests
    ├── dryrun.bats     # Dry-run mode utilities tests
    ├── json.bats       # JSON manipulation utilities tests
    ├── launchd.bats    # macOS service management tests
    └── pkg.bats        # Package manager detection tests
```

## Writing Tests

Tests use the Bats testing framework. Each test file should:

1. Source required libraries in `setup()` function
2. Use descriptive test names with `@test "description"`
3. Use assertions: `[ condition ]` for status, `[[ string =~ pattern ]]` for output
4. Clean up resources in `teardown()` if needed

### Example

```bash
#!/usr/bin/env bats

setup() {
  ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${ROOT_DIR}/scripts/lib/log.sh"
  source "${ROOT_DIR}/scripts/lib/cmd.sh"
  TAG="test"
}

@test "function returns expected value" {
  run my_function arg1 arg2
  [ "$status" -eq 0 ]
  [[ "$output" =~ "expected output" ]]
}
```

## Coverage

Current test coverage (102 tests total):

- ✅ `scripts/lib/cmd.sh` - 20 tests covering all functions
  - `has_cmd` - Silent command existence check
  - `require_cmd` - Exit if command missing
  - `check_cmd` - Log-based validation
  - `check_optional_cmd` - Non-failing validation
  - `ensure_cmd` - Install if missing

- ✅ `scripts/lib/dryrun.sh` - 19 tests covering all functions
  - `set_dryrun_mode` - Enable/disable dry-run mode
  - `is_dryrun` - Check if dry-run enabled
  - `dryrun_exec` - Execute or log commands
  - `parse_dryrun_args` - Parse --dry-run from args
  - `parse_dryrun_flag` - Check single arg for --dry-run

- ✅ `scripts/lib/json.sh` - 25 tests covering all functions
  - `merge_json_config` - Read/modify/write JSON configs
  - `read_json_value` - Read values from JSON
  - `update_json_value` - Update single JSON value
  - `validate_json` - Validate JSON syntax
  - `ensure_json_dir` - Create parent directories

- ✅ `scripts/lib/pkg.sh` - 18 tests covering all functions
  - `has_zerobrew` - Check for zerobrew (zb)
  - `has_brew` - Check for Homebrew
  - `has_apt` - Check for apt
  - `detect_pkg_manager` - Auto-detect package manager
  - `ensure_homebrew` - Require zb or brew
  - `bundle_install` - Install from Brewfile

- ✅ `scripts/lib/launchd.sh` - 20 tests covering all functions (macOS only)
  - `launchd_is_loaded` - Check if service is loaded
  - `launchd_uninstall` - Stop and remove service
  - `launchd_status` - Print service status
  - `launchd_logs` - Tail service logs
  - `launchd_stop` - Stop service
  - `launchd_start` - Start service from plist
  - `launchd_restart` - Restart service

## Adding Tests

When adding new library functions:

1. Create corresponding test file in `tests/lib/`
2. Write tests covering success and failure cases
3. Test edge cases and error handling
4. Verify tests pass: `bats tests/lib/yourfile.bats`
5. Update this README with new coverage

## CI Integration

Tests can be integrated into CI/CD pipelines:

```bash
# In GitHub Actions, GitLab CI, etc.
- name: Install bats
  run: brew install bats-core  # or apt-get install bats

- name: Run tests
  run: mise run test
```

## Known Limitations

### Array Modification in Tests

The `ensure_cmd` function's array modification via `eval` works at script global scope but not within Bats test function scope due to bash scoping rules. Tests verify the function accepts array parameters correctly rather than testing array modification directly.

This is not an issue in real usage - the function works correctly in scripts like `setup-dev-tools.sh` where arrays are declared at global scope.
