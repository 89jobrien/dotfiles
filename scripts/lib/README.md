# Scripts Library Reference

Shared utilities for dotfiles bootstrap and maintenance scripts.

## Quick Start

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load libraries (order matters: log.sh first)
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
source "${ROOT_DIR}/scripts/lib/pkg.sh"
source "${ROOT_DIR}/scripts/lib/dryrun.sh"
source "${ROOT_DIR}/scripts/lib/json.sh"
source "${ROOT_DIR}/scripts/lib/launchd.sh"  # macOS only

TAG="my-script"

# Your script logic here
require_cmd git
ensure_homebrew
log_ok "Ready to go!"
```

## Libraries

### log.sh - Logging Functions

Core logging with gum integration and JSON support for Vector. Includes secret redaction via `obfuscate.sh`.

**Functions:**
- `log "message"` - Info message
- `log_ok "message"` - Success message (green)
- `log_skip "message"` - Skip message (gray)
- `log_warn "message"` - Warning message (yellow)
- `log_err "message"` - Error message (red)
- `spin "label" command args` - Run command with spinner
- `section "name"` - Print section header
- `init_log_file PATH` - Initialize JSON log file
- `log_redacted "message"` - Log with secrets redacted

**Environment Variables:**
- `TAG` (required) - Script identifier
- `LOG_FORMAT` - Set to `json` for structured output
- `LOG_FILE` - Write logs to file (in addition to stdout)

**Example:**
```bash
TAG="deploy"
log "starting deployment"
log_ok "build succeeded"
log_warn "deprecated API detected"
log_err "deployment failed"
section "Cleanup"
```

**JSON Mode (for Vector):**
```bash
export LOG_FORMAT=json
export LOG_FILE="${HOME}/logs/ai/scripts/deploy.jsonl"
init_log_file "${LOG_FILE}"
log "deployment started"
# Output: {"timestamp":"2026-03-04T06:51:00.000Z","hostname":"...","tag":"deploy","level":"info","message":"deployment started"}
```

### obfuscate.sh - Secret Redaction

Redact secrets and obfuscate sensitive identifiers in text, files, or logs.

**Functions:**
- `obfuscate_text TEXT` - Redact secrets in text string
- `obfuscate_file INPUT [OUTPUT]` - Redact secrets in file (prints to stdout if no output file)
- `obfuscate_lines [LINES...]` - Redact secrets from multiple lines (reads from stdin or args)
- `log_redacted "message"` - Log with secrets redacted (via log.sh)

**Redacts:**
- API Keys (ANTHROPIC_API_KEY, OPENAI_API_KEY, generic *API_KEY)
- GitHub tokens (ghp_*, github_pat_*)
- AWS credentials (AWS_SECRET_ACCESS_KEY, AWS_ACCESS_KEY_ID)
- Bearer tokens and Authorization headers
- SSH public keys
- Private IP addresses (10.x, 172.16-31.x, 192.168.x)

**Usage Examples:**
```bash
# As library
source scripts/lib/obfuscate.sh
redacted=$(obfuscate_text "My API key is sk-ant-12345")
echo "$redacted"  # My API key is [REDACTED-ANTHROPIC-KEY]

# With log.sh
source scripts/lib/log.sh
log_redacted "Connecting with token=$MY_SECRET_TOKEN"  # token=[REDACTED-TOKEN]

# Standalone script
./scripts/lib/obfuscate.sh "AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG"
# AWS_SECRET_ACCESS_KEY=[REDACTED-AWS-SECRET]

# Redact file
./scripts/lib/obfuscate.sh --file logs/bootstrap.log logs/bootstrap.log.redacted

# Pipe through
docker logs mycontainer | ./scripts/lib/obfuscate.sh
```

### cmd.sh - Command Checking

Utilities for checking command availability.

**Functions:**
- `has_cmd CMD` - Returns 0 if command exists (silent)
- `require_cmd CMD [HINT]` - Exit if command missing
- `check_cmd CMD [STATUS_VAR]` - Log ok/error, optionally set status variable
- `check_optional_cmd CMD` - Log ok/skip (never sets error)
- `ensure_cmd CMD INSTALL_CMD [FAILED_ARRAY]` - Install if missing

**Examples:**
```bash
# Silent check
if has_cmd docker; then
  echo "Docker is available"
fi

# Required command (exits if missing)
require_cmd git "brew install git"

# Health check pattern (like doctor.sh)
status=0
check_cmd jq status
check_cmd yq status
check_optional_cmd gum
exit "${status}"

# Install if missing
failed=()
ensure_cmd bacon "cargo install --locked bacon" failed
if [[ ${#failed[@]} -gt 0 ]]; then
  log_warn "Failed to install: ${failed[*]}"
fi
```

### pkg.sh - Package Manager Detection

Detect and use package managers (zerobrew, Homebrew, apt).

**Functions:**
- `has_zerobrew` - Returns 0 if zb exists
- `has_brew` - Returns 0 if brew exists
- `has_apt` - Returns 0 if apt exists
- `detect_pkg_manager` - Prints "zerobrew", "homebrew", "apt", or ""
- `ensure_homebrew` - Exit if neither zb nor brew found
- `bundle_install BREWFILE` - Install packages from Brewfile

**Examples:**
```bash
# Detect package manager
PKG=$(detect_pkg_manager)
case "${PKG}" in
  zerobrew) log "Using zerobrew" ;;
  homebrew) log "Using Homebrew" ;;
  apt) log "Using apt" ;;
  *) log_err "No package manager found"; exit 1 ;;
esac

# Ensure Homebrew available
ensure_homebrew

# Install from Brewfile
bundle_install "${ROOT_DIR}/Brewfile.macos"
```

### dryrun.sh - Dry-Run Mode

Handle `--dry-run` flag and conditional execution.

**Functions:**
- `set_dryrun_mode 0|1` - Manually enable/disable
- `is_dryrun` - Returns 0 if dry-run enabled
- `dryrun_exec COMMAND [ARGS]` - Execute or log command
- `parse_dryrun_args ARGS...` - Parse --dry-run from args

**Global Variable:**
- `DRY_RUN` - 0 (disabled) or 1 (enabled)

**Examples:**
```bash
# Parse arguments
parse_dryrun_args "$@"
set -- "${DRYRUN_REMAINING_ARGS[@]}"

# Or use in case statement
case "$1" in
  --dry-run) set_dryrun_mode 1; shift ;;
esac

# Conditional execution
dryrun_exec rm -rf /tmp/cache
dryrun_exec docker system prune -af

# Manual check
if is_dryrun; then
  log "[dry-run] Would delete 42 files"
else
  find . -name '*.tmp' -delete
fi
```

### launchd.sh - macOS Service Management

LaunchDaemon/LaunchAgent utilities for macOS service management.

**Functions:**
- `launchd_is_loaded` - Check if service is loaded
- `launchd_uninstall` - Stop service and remove plist
- `launchd_status` - Print service status (exits 1 if not loaded)
- `launchd_logs` - Tail stdout/stderr logs
- `launchd_stop` - Stop service if running
- `launchd_start [PLIST]` - Start service from plist
- `launchd_restart` - Restart service (stop then start)

**Required Variables:**
- `LABEL` - Reverse DNS label (e.g., "com.user.service")
- `PLIST_PATH` - Path to plist file
- `DOMAIN` - launchd domain (e.g., "gui/${UID}")

**Optional Variables (for launchd_logs):**
- `STATE_DIR` - Directory for logs
- `STDOUT_LOG` - Path to stdout log
- `STDERR_LOG` - Path to stderr log

**Examples:**
```bash
LABEL="com.user.myservice"
DOMAIN="gui/${UID}"
PLIST_PATH="${HOME}/Library/LaunchAgents/${LABEL}.plist"
STATE_DIR="${HOME}/.local/state/myservice"
STDOUT_LOG="${STATE_DIR}/stdout.log"
STDERR_LOG="${STATE_DIR}/stderr.log"

# Check if loaded
if launchd_is_loaded; then
  log "Service is running"
fi

# Manage service
launchd_start
launchd_stop
launchd_restart
launchd_status
launchd_logs

# Uninstall
launchd_uninstall
```

### json.sh - JSON Manipulation

JSON config file manipulation using jq.

**Functions:**
- `merge_json_config FILE FILTER [--arg KEY VAL]` - Merge changes into JSON
- `read_json_value FILE PATH` - Read value from JSON
- `update_json_value FILE PATH VALUE` - Update single value
- `validate_json FILE` - Validate JSON syntax
- `ensure_json_dir FILE` - Create parent directory

**Examples:**
```bash
# Merge config (like setup-ai-tools.sh)
merge_json_config config.json '
  .servers = (.servers // {}) |
  .servers.personal = {
    command: $cmd,
    args: []
  }
' --arg cmd "/usr/local/bin/server"

# Read value
THEME=$(read_json_value config.json '.theme')

# Update value
update_json_value config.json '.enabled' 'true'

# Validate
if validate_json config.json; then
  log_ok "Valid JSON"
fi
```

## Migration Guide

### From Custom Logging to log.sh

**Before:**
```bash
echo "[my-script] Starting..."
printf '[my-script] \033[0;32mSuccess\033[0m\n'
```

**After:**
```bash
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="my-script"
log "Starting..."
log_ok "Success"
```

### From Inline Command Checks to cmd.sh

**Before:**
```bash
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found"
  exit 1
fi
```

**After:**
```bash
source "${ROOT_DIR}/scripts/lib/cmd.sh"
require_cmd docker "brew install --cask docker"
```

### From Inline Dry-Run to dryrun.sh

**Before:**
```bash
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
  esac
done

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "[dry-run] Would run: $cmd"
else
  eval "$cmd"
fi
```

**After:**
```bash
source "${ROOT_DIR}/scripts/lib/dryrun.sh"
parse_dryrun_args "$@"
set -- "${DRYRUN_REMAINING_ARGS[@]}"
dryrun_exec eval "$cmd"
```

## Vector Integration

Scripts can send structured logs to Vector for centralized collection:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
TAG="my-script"

# Enable JSON output
export LOG_FORMAT=json
export LOG_FILE="${HOME}/logs/ai/scripts/my-script.jsonl"
init_log_file "${LOG_FILE}"

# All log calls now output JSON to both stdout and file
log "Script started"
log_ok "Operation completed"

# Vector will collect from ${LOG_FILE} and store in ~/logs/ai/vector/
```

Vector configuration: `vector/.config/vector/vector.yaml`
Vector service: `scripts/vector-service.sh install`

## Best Practices

1. **Always source log.sh first** - Other libraries may use logging
2. **Set TAG before any log calls** - Required for proper identification
3. **Use require_cmd for critical dependencies** - Fail fast with helpful errors
4. **Use ensure_cmd for optional tools** - Continue on failure, track results
5. **Add --dry-run support** - Makes scripts safer for testing
6. **Use JSON mode for long-running scripts** - Better integration with Vector

## Testing

### Automated Tests

All libraries have comprehensive bats test suites (102 tests total):

```bash
# Run all library tests
bats tests/lib/*.bats

# Run specific library tests
bats tests/lib/cmd.bats      # 20 tests - command checking
bats tests/lib/dryrun.bats   # 19 tests - dry-run mode
bats tests/lib/json.bats     # 25 tests - JSON manipulation
bats tests/lib/pkg.bats      # 18 tests - package manager detection
bats tests/lib/launchd.bats  # 20 tests - macOS service management

# Run via mise
mise run test          # All tests
mise run test-lib      # Just library tests
```

**Test Coverage:**
- ✅ `cmd.sh` - 20 tests covering all functions and edge cases
- ✅ `dryrun.sh` - 19 tests covering mode control, execution, and arg parsing
- ✅ `json.sh` - 25 tests covering config merging, validation, and real-world scenarios
- ✅ `pkg.sh` - 18 tests covering package manager detection and installation
- ✅ `launchd.sh` - 20 tests covering macOS service management and control

See `tests/README.md` for detailed test documentation.

### Manual Verification

```bash
# Check system health
mise run doctor

# Individual library smoke tests
bash -c 'source scripts/lib/log.sh; source scripts/lib/cmd.sh; TAG="test"; has_cmd bash && echo PASS'
bash -c 'source scripts/lib/log.sh; source scripts/lib/pkg.sh; TAG="test"; detect_pkg_manager'
bash -c 'source scripts/lib/log.sh; source scripts/lib/dryrun.sh; TAG="test"; set_dryrun_mode 1; dryrun_exec echo test'
bash -c 'source scripts/lib/log.sh; source scripts/lib/cmd.sh; source scripts/lib/json.sh; TAG="test"; echo "{}" | jq . > /tmp/test.json; merge_json_config /tmp/test.json ".foo = \"bar\""; cat /tmp/test.json'
```

## See Also

- `scripts-refactoring-analysis.md` - Detailed refactoring analysis
- Individual script headers for specific usage examples
- `.mise.toml` - Task definitions using these libraries
