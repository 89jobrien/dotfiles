# Scripts Refactoring Analysis

**Date:** 2026-03-04
**Scope:** /Users/joe/dotfiles/scripts directory

## Executive Summary

Analysis of 25+ shell scripts reveals excellent adoption of scripts/lib/log.sh (23/25 scripts) with opportunities to
extract 4 major repetitive patterns into shared libraries. Key findings:

- 92% of scripts already use standardized logging (scripts/lib/log.sh)
- 4 distinct repetitive patterns identified across scripts
- 2 scripts need log.sh adoption (claude-log-retention.sh, post-bootstrap.local.example.sh)
- Strong consistency in script structure (set -euo pipefail, ROOT_DIR pattern, TAG naming)

## Current State Assessment

### Scripts Using log.sh (23/25)

All major scripts properly source scripts/lib/log.sh and set TAG:

```text
bootstrap.sh, setup-nix.sh, setup-ai-tools.sh, doctor.sh, drift-check.sh,
setup-dev-tools.sh, setup-companion-repos.sh, setup-secrets.sh,
setup-git-config.sh, setup-macos.sh, setup-oh-my-zsh.sh, setup-zerobrew.sh,
setup-maestro.sh, system-health.sh, container-dev.sh, rust-clean.sh,
setup-nvchad-avante.sh, compose-dev.sh, maestro-dev.sh, observe-dev.sh,
rust-clean-service.sh, vector-retention-service.sh, vector-service.sh
```

### Scripts NOT Using log.sh (2/25)

1. **claude-log-retention.sh** - Uses printf-based logging, candidate for refactoring
2. **post-bootstrap.local.example.sh** - Template file (intentionally minimal)

### Non-Shell Scripts (1)

- **claude-log-dashboard.py** - Python script (out of scope)

## Repetitive Patterns Identified

### 1. Command Availability Checking

**Pattern:** Multiple variants across scripts checking if commands exist

**Locations:**

- `doctor.sh`: `check_cmd()`, `check_optional_cmd()`
- `setup-dev-tools.sh`: `ensure_cmd()`
- `container-dev.sh`: `need_cmd()`
- `bootstrap.sh`: Inline `command -v` checks

**Current Implementations:**

```bash
# doctor.sh
check_cmd() {
  local cmd="$1"
  if command -v "${cmd}" >/dev/null 2>&1; then
    log_ok "${cmd} -> $(command -v "${cmd}")"
  else
    log_err "${cmd} missing"
    status=1
  fi
}

# setup-dev-tools.sh
ensure_cmd() {
  local cmd="$1"
  local install_cmd="$2"
  if command -v "${cmd}" >/dev/null 2>&1; then
    return 0
  fi
  log "installing ${cmd}..."
  if ! eval "${install_cmd}"; then
    log_warn "failed to install ${cmd}; continuing"
    failed_optional+=("${cmd}")
    return 1
  fi
}

# container-dev.sh
need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_err "missing required command: $1"
    exit 1
  fi
}
```

**Proposed Shared Function:**

```bash
# scripts/lib/helpers.sh

# Check if command exists (non-fatal)
has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# Require command or exit with error
require_cmd() {
  local cmd="$1"
  local msg="${2:-missing required command: $cmd}"
  if ! has_cmd "${cmd}"; then
    log_err "${msg}"
    exit 1
  fi
}

# Check command with logging
check_cmd() {
  local cmd="$1"
  if has_cmd "${cmd}"; then
    log_ok "${cmd} -> $(command -v "${cmd}")"
    return 0
  else
    log_err "${cmd} missing"
    return 1
  fi
}

# Check optional command with logging
check_optional_cmd() {
  local cmd="$1"
  if has_cmd "${cmd}"; then
    log_ok "${cmd} -> $(command -v "${cmd}")"
  else
    log_skip "${cmd} (optional)"
  fi
}

# Install command if missing
ensure_cmd() {
  local cmd="$1"
  local install_cmd="$2"
  if has_cmd "${cmd}"; then
    return 0
  fi
  log "installing ${cmd}..."
  if eval "${install_cmd}"; then
    return 0
  else
    log_warn "failed to install ${cmd}"
    return 1
  fi
}
```

### 2. Package Manager Detection

**Pattern:** Detecting zerobrew/brew/apt across multiple scripts

**Locations:**

- `bootstrap.sh`: `ensure_homebrew()`, `check_homebrew_writable()`
- `setup-ai-tools.sh`: `install_opencode_if_missing()` (zb/brew detection)

**Current Implementation:**

```bash
# bootstrap.sh
ensure_homebrew() {
  if command -v zb >/dev/null 2>&1; then
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$(uname -s)" == "Darwin" ]]; then
    log "installing Homebrew (macOS)..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    return 0
  fi
  # ... Linux fallback
}
```

**Proposed Shared Functions:**

```bash
# scripts/lib/helpers.sh

# Get package manager command (zb > brew > apt)
get_pkg_manager() {
  if has_cmd zb; then
    echo "zb"
  elif has_cmd brew; then
    echo "brew"
  elif has_cmd apt-get; then
    echo "apt-get"
  else
    return 1
  fi
}

# Install package using detected package manager
pkg_install() {
  local pkg="$1"
  local mgr
  mgr="$(get_pkg_manager)" || {
    log_err "no supported package manager found"
    return 1
  }

  case "${mgr}" in
    zb) zb install "${pkg}" ;;
    brew) brew install "${pkg}" ;;
    apt-get) sudo apt-get install -y "${pkg}" ;;
  esac
}
```

### 3. Dry-Run Pattern

**Pattern:** Inconsistent dry-run implementations

**Locations:**

- `claude-log-retention.sh`: `DRY_RUN=0` + `run()` function
- `rust-clean.sh`: `RUST_CLEAN_DRY_RUN` + inline checks
- `setup-maestro.sh`: `DRY_RUN=0` + `run_cmd()` function

**Current Implementations:**

```bash
# claude-log-retention.sh
run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

# setup-maestro.sh
run_cmd() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    log "[dry-run] $*"
    return 0
  fi
  "$@"
}

# rust-clean.sh
if [[ "${DRY_RUN}" == "1" ]]; then
  log "dry-run: artifacts older than ${KEEP_DAYS} days under ${SCAN_DIR}"
  cargo sweep --time "${KEEP_DAYS}" --recursive --dry-run "${SCAN_DIR}"
else
  # actual run
fi
```

**Proposed Shared Function:**

```bash
# scripts/lib/helpers.sh

DRY_RUN="${DRY_RUN:-0}"

# Execute command with dry-run support
dry_run() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    log "[dry-run] $*"
    return 0
  fi
  "$@"
}

# Check if in dry-run mode
is_dry_run() {
  [[ "${DRY_RUN}" == "1" ]]
}
```

### 4. JSON Config Manipulation

**Pattern:** JSON merge/update using jq (currently only in setup-ai-tools.sh but powerful pattern)

**Location:**

- `setup-ai-tools.sh`: `merge_json_config()` function

**Current Implementation:**

```bash
# setup-ai-tools.sh
merge_json_config() {
  local cfg="$1" filter="$2"
  shift 2
  local tmp
  tmp="$(mktemp)"
  if [[ -f "${cfg}" ]]; then
    cp "${cfg}" "${tmp}"
  else
    printf '{}' > "${tmp}"
  fi
  jq "$@" "${filter}" "${tmp}" > "${tmp}.new"
  mv "${tmp}.new" "${cfg}"
  rm -f "${tmp}"
}
```

**Proposed Shared Library:**

```bash
# scripts/lib/json.sh

# Merge JSON config file with jq filter
json_merge() {
  local cfg="$1" filter="$2"
  shift 2

  require_cmd jq "jq is required for JSON manipulation"

  local tmp
  tmp="$(mktemp)"

  if [[ -f "${cfg}" ]]; then
    cp "${cfg}" "${tmp}"
  else
    printf '{}' > "${tmp}"
  fi

  if ! jq "$@" "${filter}" "${tmp}" > "${tmp}.new"; then
    rm -f "${tmp}" "${tmp}.new"
    log_err "jq filter failed"
    return 1
  fi

  mv "${tmp}.new" "${cfg}"
  rm -f "${tmp}"
}

# Get value from JSON file
json_get() {
  local file="$1" query="$2"
  require_cmd jq
  jq -r "${query}" "${file}"
}

# Set value in JSON file
json_set() {
  local file="$1" path="$2" value="$3"
  json_merge "${file}" --arg val "${value}" "${path} = \$val"
}
```

## Additional Patterns Worth Extracting

### 5. System Detection

**Pattern:** OS/architecture detection

**Locations:**

- `setup-nix.sh`: `resolve_system()`
- Multiple scripts: `uname -s` checks

**Proposed:**

```bash
# scripts/lib/helpers.sh

is_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}

is_linux() {
  [[ "$(uname -s)" == "Linux" ]]
}

get_arch() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    arm64) echo "aarch64" ;;
    *) echo "${arch}" ;;
  esac
}

get_system() {
  local kernel
  kernel="$(uname -s | tr '[:upper:]' '[:lower:]')"
  printf '%s-%s' "$(get_arch)" "${kernel}"
}
```

### 6. Interactive Input

**Pattern:** gum-aware input prompting

**Location:**

- `setup-git-config.sh`: `prompt_value()`

**Proposed:**

```bash
# scripts/lib/helpers.sh

# Prompt for user input (gum-aware)
prompt() {
  local label="$1"
  local default="${2:-}"

  if [[ ! -t 0 ]]; then
    echo "${default}"
    return 0
  fi

  if has_cmd gum; then
    gum input --placeholder "${label}" --value "${default}" --prompt "> " || echo "${default}"
  else
    local value
    read -r -p "${label}: " value || echo "${default}"
    [[ -n "${value}" ]] && echo "${value}" || echo "${default}"
  fi
}

# Confirm action (gum-aware)
confirm() {
  local msg="${1:-Proceed?}"

  if [[ ! -t 0 ]]; then
    return 1
  fi

  if has_cmd gum; then
    gum confirm "${msg}"
  else
    local answer
    read -r -p "${msg} [y/N] " answer
    [[ "${answer}" =~ ^[Yy] ]]
  fi
}
```

## Script Quality Observations

### Strengths

1. **Consistent Structure:** All scripts follow the same header pattern:

   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
   source "${ROOT_DIR}/scripts/lib/log.sh"
   TAG="name"
   ```

2. **Good Separation of Concerns:** Scripts are well-organized with clear functions

3. **Error Handling:** Most scripts properly handle errors with informative messages

4. **Idempotency:** Scripts check state before acting (skip if already done)

### Areas for Improvement

1. **Command Checking Inconsistency:** 3 different patterns (check_cmd, ensure_cmd, need_cmd)

2. **No Shellcheck Integration:** No automated validation of shell scripts

3. **Dry-Run Pattern Variance:** Each script implements dry-run differently

4. **Limited Testing:** No unit/integration tests for scripts

5. **Documentation Gaps:**
   - No inline function documentation
   - Missing scripts architecture documentation

## Recommendations

### Priority 1: Create Core Library

Create `/Users/joe/dotfiles/scripts/lib/helpers.sh` with:

- Command availability functions (has_cmd, require_cmd, check_cmd, etc.)
- Package manager detection (get_pkg_manager, pkg_install)
- Dry-run support (dry_run, is_dry_run)
- System detection (is_macos, is_linux, get_arch, get_system)
- Interactive input (prompt, confirm)

### Priority 2: Refactor Existing Scripts

1. Update `claude-log-retention.sh` to use log.sh
2. Replace inline command checks with helpers.sh functions
3. Standardize dry-run pattern using shared functions
4. Extract bootstrap.sh package manager logic

### Priority 3: Add Quality Tooling

1. Integrate shellcheck into mise tasks
2. Add pre-commit hook for shell script validation
3. Consider bats for script testing

### Priority 4: Documentation

1. Create SCRIPTS.md documenting:
   - Script architecture
   - Library usage patterns
   - Contribution guidelines
2. Add inline documentation to all functions
3. Document environment variables used by each script

## Proposed File Structure

```text
scripts/
├── lib/
│   ├── log.sh          # Existing - standardized logging
│   ├── helpers.sh      # NEW - common utility functions
│   └── json.sh         # NEW - JSON manipulation helpers
├── bootstrap.sh        # Core bootstrap orchestrator
├── setup-*.sh          # Setup phase scripts
├── *-dev.sh           # Developer workflow scripts
├── *-service.sh       # Background service scripts
└── *.sh               # Utility scripts
```

## Migration Path

### Phase 1: Foundation (Week 1)

- Create scripts/lib/helpers.sh
- Create scripts/lib/json.sh
- Add shellcheck to mise tasks

### Phase 2: High-Impact Refactors (Week 2)

- Refactor claude-log-retention.sh to use log.sh
- Update bootstrap.sh to use helpers.sh
- Update setup-ai-tools.sh to use json.sh
- Standardize all command checks

### Phase 3: Comprehensive Updates (Week 3)

- Update all remaining scripts to use helpers.sh
- Standardize dry-run pattern across all scripts
- Add function documentation

### Phase 4: Quality & Documentation (Week 4)

- Create SCRIPTS.md
- Add pre-commit shellcheck hook
- Consider adding bats tests for critical scripts

## Impact Assessment

### Benefits

1. **Reduced Code Duplication:** ~200 lines eliminated across scripts
2. **Consistency:** Single implementation of common patterns
3. **Maintainability:** Changes to patterns only need to update one location
4. **Testing:** Shared functions can be unit tested
5. **Onboarding:** New contributors have clear patterns to follow

### Risks

1. **Breaking Changes:** Refactoring could introduce regressions
2. **Testing Overhead:** New shared libraries need comprehensive testing
3. **Migration Effort:** 20+ scripts need updates

### Mitigation

1. Keep existing scripts working during migration
2. Add each shared function incrementally with tests
3. Migrate one script at a time, validate with doctor.sh
4. Use mise run doctor as regression test

## Example Refactor: claude-log-retention.sh

### Before (Current)

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${AI_LOG_ROOT:-${HOME}/logs/ai}"
# ... no logging library
# ... custom run() function for dry-run
# ... inline printf for output
```

### After (Proposed)

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/helpers.sh"
TAG="log-retention"

AI_LOG_ROOT="${AI_LOG_ROOT:-${HOME}/logs/ai}"
RETENTION_DAYS="${AI_LOG_RETENTION_DAYS:-180}"
COMPRESS_AFTER_DAYS="${AI_LOG_COMPRESS_AFTER_DAYS:-14}"

# ... use dry_run() from helpers.sh
# ... use log_*() functions from log.sh
# ... consistent with other scripts
```

## Task Checklist

All tasks have been added to doob for tracking:

1. [Priority 1] Create scripts/lib/helpers.sh with common utility functions
2. [Priority 2] Refactor claude-log-retention.sh to use scripts/lib/log.sh
3. [Priority 2] Extract command checking pattern to shared library
4. [Priority 2] Extract package manager detection logic to shared library
5. [Priority 2] Add shellcheck validation to all scripts
6. [Priority 3] Standardize dry-run pattern across all scripts
7. [Priority 3] Create scripts/lib/json.sh for JSON helpers
8. [Priority 3] Document script architecture in SCRIPTS.md

View tasks: `doob todo list --tag scripts`

## Conclusion

The scripts directory is already well-structured with excellent log.sh adoption. The proposed refactoring will:

- Extract 4 major repetitive patterns into 2 new shared libraries
- Reduce code duplication by ~200 lines
- Improve consistency across all scripts
- Enable better testing and maintainability
- Provide clear patterns for future script development

The migration can be done incrementally over 4 weeks with minimal risk and high reward.
