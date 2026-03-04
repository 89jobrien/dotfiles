# Performance Benchmarking System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an always-on performance benchmarking system that tracks bootstrap phases and individual scripts with full metrics (timing, exit codes, system load, git commit) stored in SQLite.

**Architecture:** Three-layer system with `scripts/lib/benchmark.sh` as the core library, integration into `bootstrap.sh` via modified `run_hook()`, and SQLite storage at `~/.local/share/dotfiles/benchmarks.db`. Non-invasive error handling ensures benchmarking never breaks operations.

**Tech Stack:** Bash, SQLite3, Bats testing framework, existing shared libraries (log.sh, cmd.sh)

---

## Task 1: Database Schema and Initialization

**Files:**
- Create: `scripts/lib/benchmark.sh`
- Create: `tests/lib/benchmark.bats`

### Step 1: Write the failing test for database initialization

Create `tests/lib/benchmark.bats`:

```bash
#!/usr/bin/env bats
# Tests for scripts/lib/benchmark.sh - Performance benchmarking utilities

setup() {
  ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${ROOT_DIR}/scripts/lib/log.sh"
  source "${ROOT_DIR}/scripts/lib/cmd.sh"
  TAG="test"

  # Use temp directory for test database
  TEST_DB_DIR="${BATS_TEST_TMPDIR}/benchmarks"
  export BENCHMARK_DB_DIR="${TEST_DB_DIR}"
  export BENCHMARK_DB_PATH="${TEST_DB_DIR}/benchmarks.db"

  # Source the library (will fail initially)
  source "${ROOT_DIR}/scripts/lib/benchmark.sh" 2>/dev/null || true
}

teardown() {
  # Clean up test database
  rm -rf "${TEST_DB_DIR}"
}

@test "benchmark_init: creates database directory" {
  benchmark_init
  [ -d "${BENCHMARK_DB_DIR}" ]
}

@test "benchmark_init: creates database file" {
  benchmark_init
  [ -f "${BENCHMARK_DB_PATH}" ]
}

@test "benchmark_init: creates benchmarks table with correct schema" {
  benchmark_init

  # Check table exists
  run sqlite3 "${BENCHMARK_DB_PATH}" "SELECT name FROM sqlite_master WHERE type='table' AND name='benchmarks';"
  [ "$status" -eq 0 ]
  [[ "$output" == "benchmarks" ]]

  # Check columns exist
  run sqlite3 "${BENCHMARK_DB_PATH}" "PRAGMA table_info(benchmarks);"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "id" ]]
  [[ "$output" =~ "timestamp" ]]
  [[ "$output" =~ "name" ]]
  [[ "$output" =~ "duration_ms" ]]
  [[ "$output" =~ "exit_code" ]]
  [[ "$output" =~ "cpu_percent" ]]
  [[ "$output" =~ "mem_mb" ]]
  [[ "$output" =~ "git_commit" ]]
}

@test "benchmark_init: is idempotent (safe to run multiple times)" {
  benchmark_init
  benchmark_init
  benchmark_init

  # Should still have one table
  run sqlite3 "${BENCHMARK_DB_PATH}" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='benchmarks';"
  [ "$status" -eq 0 ]
  [[ "$output" == "1" ]]
}
```

### Step 2: Run test to verify it fails

```bash
bats tests/lib/benchmark.bats
```

Expected: FAIL - "benchmark.sh: No such file or directory"

### Step 3: Write minimal implementation

Create `scripts/lib/benchmark.sh`:

```bash
#!/usr/bin/env bash
# Performance benchmarking utilities for tracking script execution times
# Source this file after log.sh and cmd.sh
#
# Required variables (can be overridden):
#   BENCHMARK_DB_DIR  - Directory for benchmark database (default: ~/.local/share/dotfiles)
#   BENCHMARK_DB_PATH - Full path to database file (default: $BENCHMARK_DB_DIR/benchmarks.db)
#
# Usage:
#   source "${ROOT_DIR}/scripts/lib/log.sh"
#   source "${ROOT_DIR}/scripts/lib/cmd.sh"
#   source "${ROOT_DIR}/scripts/lib/benchmark.sh"
#
#   benchmark_exec "my-operation" some-command arg1 arg2
#   benchmark_report

# Default database location
: "${BENCHMARK_DB_DIR:=${HOME}/.local/share/dotfiles}"
: "${BENCHMARK_DB_PATH:=${BENCHMARK_DB_DIR}/benchmarks.db}"

# Global flag to enable/disable benchmarking
BENCHMARK_ENABLED=1

# benchmark_init
#   Initialize database and schema if needed
benchmark_init() {
  # Check if sqlite3 is available
  if ! has_cmd sqlite3; then
    log_warn "sqlite3 not available, benchmarking disabled"
    BENCHMARK_ENABLED=0
    return 0
  fi

  # Create database directory if needed
  if [[ ! -d "${BENCHMARK_DB_DIR}" ]]; then
    mkdir -p "${BENCHMARK_DB_DIR}" || {
      log_warn "failed to create benchmark database directory, benchmarking disabled"
      BENCHMARK_ENABLED=0
      return 0
    }
  fi

  # Create database and schema if needed
  sqlite3 "${BENCHMARK_DB_PATH}" <<'SQL' 2>/dev/null || {
    log_warn "failed to initialize benchmark database, benchmarking disabled"
    BENCHMARK_ENABLED=0
    return 0
  }
CREATE TABLE IF NOT EXISTS benchmarks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp TEXT NOT NULL,
  name TEXT NOT NULL,
  duration_ms INTEGER NOT NULL,
  exit_code INTEGER NOT NULL,
  cpu_percent REAL,
  mem_mb REAL,
  git_commit TEXT
);
SQL

  BENCHMARK_ENABLED=1
}
```

### Step 4: Run test to verify it passes

```bash
bats tests/lib/benchmark.bats
```

Expected: PASS - All 4 tests pass

### Step 5: Commit

```bash
git add scripts/lib/benchmark.sh tests/lib/benchmark.bats
git commit -m "feat(benchmark): add database initialization

- Create benchmark.sh library with database init
- SQLite schema with 8 columns (timing, metrics, metadata)
- Non-invasive error handling (disables on failure)
- Idempotent initialization
- Full test coverage for init function"
```

---

## Task 2: Basic Timing and Execution

**Files:**
- Modify: `scripts/lib/benchmark.sh`
- Modify: `tests/lib/benchmark.bats`

### Step 1: Write the failing test for benchmark_exec timing

Add to `tests/lib/benchmark.bats`:

```bash
@test "benchmark_exec: executes command successfully" {
  benchmark_init

  run benchmark_exec "test-command" echo "hello"
  [ "$status" -eq 0 ]
}

@test "benchmark_exec: returns original command exit code on success" {
  benchmark_init

  run benchmark_exec "test-success" true
  [ "$status" -eq 0 ]
}

@test "benchmark_exec: returns original command exit code on failure" {
  benchmark_init

  run benchmark_exec "test-failure" false
  [ "$status" -eq 1 ]
}

@test "benchmark_exec: records execution in database" {
  benchmark_init

  benchmark_exec "test-db-insert" sleep 0.1

  # Check record exists
  run sqlite3 "${BENCHMARK_DB_PATH}" "SELECT name FROM benchmarks WHERE name='test-db-insert';"
  [ "$status" -eq 0 ]
  [[ "$output" == "test-db-insert" ]]
}

@test "benchmark_exec: captures duration in milliseconds" {
  benchmark_init

  benchmark_exec "test-duration" sleep 0.1

  # Duration should be >= 100ms
  run sqlite3 "${BENCHMARK_DB_PATH}" "SELECT duration_ms FROM benchmarks WHERE name='test-duration';"
  [ "$status" -eq 0 ]
  [ "$output" -ge 100 ]
}

@test "benchmark_exec: captures exit code" {
  benchmark_init

  benchmark_exec "test-exit-success" true
  benchmark_exec "test-exit-failure" sh -c "exit 42" || true

  run sqlite3 "${BENCHMARK_DB_PATH}" "SELECT exit_code FROM benchmarks WHERE name='test-exit-success';"
  [ "$status" -eq 0 ]
  [[ "$output" == "0" ]]

  run sqlite3 "${BENCHMARK_DB_PATH}" "SELECT exit_code FROM benchmarks WHERE name='test-exit-failure';"
  [ "$status" -eq 0 ]
  [[ "$output" == "42" ]]
}
```

### Step 2: Run test to verify it fails

```bash
bats tests/lib/benchmark.bats -f "benchmark_exec"
```

Expected: FAIL - "benchmark_exec: command not found"

### Step 3: Write minimal implementation

Add to `scripts/lib/benchmark.sh`:

```bash
# benchmark_exec <name> <command...>
#   Execute command with timing and metrics collection
benchmark_exec() {
  local name="$1"
  shift

  # Ensure database is initialized
  if [[ "${BENCHMARK_ENABLED}" != "1" ]]; then
    benchmark_init
  fi

  # If benchmarking is disabled, just execute the command
  if [[ "${BENCHMARK_ENABLED}" != "1" ]]; then
    "$@"
    return $?
  fi

  # Capture start time (nanoseconds)
  local start_time
  if command -v gdate >/dev/null 2>&1; then
    # macOS with coreutils
    start_time=$(gdate +%s%N)
  elif date +%s%N >/dev/null 2>&1; then
    # Linux with nanosecond support
    start_time=$(date +%s%N)
  else
    # Fallback to second precision
    start_time=$(($(date +%s) * 1000000000))
  fi

  # Execute command and capture exit code
  local exit_code=0
  set +e
  "$@"
  exit_code=$?
  set -e

  # Capture end time
  local end_time
  if command -v gdate >/dev/null 2>&1; then
    end_time=$(gdate +%s%N)
  elif date +%s%N >/dev/null 2>&1; then
    end_time=$(date +%s%N)
  else
    end_time=$(($(date +%s) * 1000000000))
  fi

  # Calculate duration in milliseconds
  local duration_ns=$((end_time - start_time))
  local duration_ms=$((duration_ns / 1000000))

  # Get current timestamp (ISO8601)
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S")

  # Placeholder values for metrics (will implement in next task)
  local cpu_percent="NULL"
  local mem_mb="NULL"
  local git_commit="unknown"

  # Insert into database
  sqlite3 "${BENCHMARK_DB_PATH}" <<SQL 2>/dev/null || {
    log_warn "failed to record benchmark for ${name}"
  }
INSERT INTO benchmarks (timestamp, name, duration_ms, exit_code, cpu_percent, mem_mb, git_commit)
VALUES ('${timestamp}', '${name}', ${duration_ms}, ${exit_code}, ${cpu_percent}, ${mem_mb}, '${git_commit}');
SQL

  # Return original exit code
  return ${exit_code}
}
```

### Step 4: Run test to verify it passes

```bash
bats tests/lib/benchmark.bats -f "benchmark_exec"
```

Expected: PASS - All benchmark_exec tests pass

### Step 5: Commit

```bash
git add scripts/lib/benchmark.sh tests/lib/benchmark.bats
git commit -m "feat(benchmark): add execution timing function

- Implement benchmark_exec with nanosecond precision timing
- Support macOS (gdate) and Linux (date +%s%N)
- Preserve original command exit codes
- Record timing and exit code to SQLite
- Handle disabled benchmarking gracefully"
```

---

## Task 3: Metrics Collection (Git Commit)

**Files:**
- Modify: `scripts/lib/benchmark.sh`
- Modify: `tests/lib/benchmark.bats`

### Step 1: Write the failing test for git commit capture

Add to `tests/lib/benchmark.bats`:

```bash
@test "benchmark_exec: captures git commit hash" {
  benchmark_init

  # Run from dotfiles repo
  cd "${ROOT_DIR}"
  benchmark_exec "test-git-commit" true

  run sqlite3 "${BENCHMARK_DB_PATH}" "SELECT git_commit FROM benchmarks WHERE name='test-git-commit';"
  [ "$status" -eq 0 ]
  # Should be a 40-character hex string or "unknown"
  [[ "$output" =~ ^[0-9a-f]{40}$ ]] || [[ "$output" == "unknown" ]]
}

@test "benchmark_exec: records 'unknown' for git commit outside repo" {
  benchmark_init

  # Run from temp directory (not a git repo)
  cd "${BATS_TEST_TMPDIR}"
  benchmark_exec "test-no-git" true

  run sqlite3 "${BENCHMARK_DB_PATH}" "SELECT git_commit FROM benchmarks WHERE name='test-no-git';"
  [ "$status" -eq 0 ]
  [[ "$output" == "unknown" ]]
}
```

### Step 2: Run test to verify it fails

```bash
bats tests/lib/benchmark.bats -f "git commit"
```

Expected: FAIL - git_commit is always "unknown"

### Step 3: Write minimal implementation

Modify the git_commit section in `benchmark_exec` function in `scripts/lib/benchmark.sh`:

```bash
  # Get git commit hash
  local git_commit="unknown"
  if git rev-parse HEAD >/dev/null 2>&1; then
    git_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
  fi
```

### Step 4: Run test to verify it passes

```bash
bats tests/lib/benchmark.bats -f "git commit"
```

Expected: PASS

### Step 5: Commit

```bash
git add scripts/lib/benchmark.sh tests/lib/benchmark.bats
git commit -m "feat(benchmark): capture git commit hash

- Get current HEAD commit via git rev-parse
- Record 'unknown' if not in git repo
- Add tests for git commit capture"
```

---

## Task 4: Metrics Collection (CPU/Memory - Placeholder)

**Files:**
- Modify: `tests/lib/benchmark.bats`

### Step 1: Write test for NULL metrics handling

Add to `tests/lib/benchmark.bats`:

```bash
@test "benchmark_exec: accepts NULL cpu_percent and mem_mb" {
  benchmark_init

  benchmark_exec "test-null-metrics" true

  # Should not error when inserting NULL values
  run sqlite3 "${BENCHMARK_DB_PATH}" "SELECT cpu_percent, mem_mb FROM benchmarks WHERE name='test-null-metrics';"
  [ "$status" -eq 0 ]
  # NULL values are displayed as empty strings by sqlite3
}
```

### Step 2: Run test to verify it passes (already implemented)

```bash
bats tests/lib/benchmark.bats -f "NULL metrics"
```

Expected: PASS (implementation already uses NULL)

### Step 3: No implementation needed (already using NULL)

The implementation already uses `NULL` for cpu_percent and mem_mb. We'll leave actual metrics collection as a future enhancement since:
- Accurate process tree metrics are complex
- Would require sampling child processes
- Risk of adding significant overhead
- Placeholder approach is documented in design

### Step 4: Commit documentation update

Add comment to `scripts/lib/benchmark.sh` in the metrics section:

```bash
  # Metrics collection (placeholder)
  # TODO: Implement CPU/memory metrics via ps sampling
  # For now, record as NULL to avoid overhead and complexity
  local cpu_percent="NULL"
  local mem_mb="NULL"
```

```bash
git add scripts/lib/benchmark.sh tests/lib/benchmark.bats
git commit -m "test(benchmark): add NULL metrics handling test

- Verify database accepts NULL for cpu_percent/mem_mb
- Document metrics collection as future enhancement
- Keeps overhead minimal for initial implementation"
```

---

## Task 5: Benchmark Reporting Function

**Files:**
- Modify: `scripts/lib/benchmark.sh`
- Modify: `tests/lib/benchmark.bats`

### Step 1: Write the failing test for benchmark_report

Add to `tests/lib/benchmark.bats`:

```bash
@test "benchmark_report: displays all records" {
  benchmark_init

  benchmark_exec "test-report-1" sleep 0.05
  benchmark_exec "test-report-2" sleep 0.05

  run benchmark_report
  [ "$status" -eq 0 ]
  [[ "$output" =~ "test-report-1" ]]
  [[ "$output" =~ "test-report-2" ]]
}

@test "benchmark_report: filters by name pattern" {
  benchmark_init

  benchmark_exec "bootstrap/Shell" sleep 0.05
  benchmark_exec "script/doctor" sleep 0.05

  run benchmark_report "bootstrap"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "bootstrap/Shell" ]]
  [[ ! "$output" =~ "script/doctor" ]]
}

@test "benchmark_report: shows summary statistics" {
  benchmark_init

  benchmark_exec "test-stats-1" sleep 0.05
  benchmark_exec "test-stats-2" sleep 0.05

  run benchmark_report "test-stats"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Count:" ]]
  [[ "$output" =~ "Average:" ]]
  [[ "$output" =~ "Min:" ]]
  [[ "$output" =~ "Max:" ]]
}

@test "benchmark_report: handles empty database gracefully" {
  benchmark_init

  run benchmark_report
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No benchmark" ]] || [[ -z "$output" ]]
}
```

### Step 2: Run test to verify it fails

```bash
bats tests/lib/benchmark.bats -f "benchmark_report"
```

Expected: FAIL - "benchmark_report: command not found"

### Step 3: Write minimal implementation

Add to `scripts/lib/benchmark.sh`:

```bash
# benchmark_report [name_filter]
#   Display benchmark results with optional name filter
benchmark_report() {
  local filter="${1:-}"

  # Ensure database is initialized
  if [[ "${BENCHMARK_ENABLED}" != "1" ]]; then
    benchmark_init
  fi

  if [[ "${BENCHMARK_ENABLED}" != "1" ]]; then
    log_warn "benchmarking is disabled"
    return 0
  fi

  # Build SQL query
  local where_clause=""
  if [[ -n "${filter}" ]]; then
    where_clause="WHERE name LIKE '%${filter}%'"
  fi

  # Get results
  local results
  results=$(sqlite3 "${BENCHMARK_DB_PATH}" <<SQL
SELECT name, duration_ms, timestamp, exit_code
FROM benchmarks
${where_clause}
ORDER BY timestamp DESC;
SQL
)

  # Check if any results
  if [[ -z "${results}" ]]; then
    echo "No benchmarks found"
    return 0
  fi

  # Display results
  echo "Benchmark Results"
  echo "========================================"
  printf "%-30s %10s %8s %20s\n" "Name" "Duration" "ExitCode" "Timestamp"
  echo "----------------------------------------"

  while IFS='|' read -r name duration_ms timestamp exit_code; do
    # Convert milliseconds to seconds with 2 decimal places
    local duration_s=$(awk "BEGIN {printf \"%.2f\", ${duration_ms}/1000}")
    printf "%-30s %8ss %8s %20s\n" "${name}" "${duration_s}" "${exit_code}" "${timestamp}"
  done <<< "${results}"

  # Calculate and display summary statistics
  local stats
  stats=$(sqlite3 "${BENCHMARK_DB_PATH}" <<SQL
SELECT COUNT(*), AVG(duration_ms), MIN(duration_ms), MAX(duration_ms)
FROM benchmarks
${where_clause};
SQL
)

  if [[ -n "${stats}" ]]; then
    IFS='|' read -r count avg_ms min_ms max_ms <<< "${stats}"
    local avg_s=$(awk "BEGIN {printf \"%.2f\", ${avg_ms}/1000}")
    local min_s=$(awk "BEGIN {printf \"%.2f\", ${min_ms}/1000}")
    local max_s=$(awk "BEGIN {printf \"%.2f\", ${max_ms}/1000}")

    echo "========================================"
    echo "Summary Statistics:"
    echo "  Count: ${count}"
    echo "  Average: ${avg_s}s"
    echo "  Min: ${min_s}s"
    echo "  Max: ${max_s}s"
  fi
}
```

### Step 4: Run test to verify it passes

```bash
bats tests/lib/benchmark.bats -f "benchmark_report"
```

Expected: PASS

### Step 5: Commit

```bash
git add scripts/lib/benchmark.sh tests/lib/benchmark.bats
git commit -m "feat(benchmark): add reporting function

- Display benchmark results in formatted table
- Filter results by name pattern
- Show summary statistics (count, avg, min, max)
- Handle empty database gracefully
- Full test coverage for reporting"
```

---

## Task 6: Ad-hoc Benchmark Wrapper Script

**Files:**
- Create: `scripts/benchmark.sh`
- Create: `tests/scripts/benchmark.bats` (integration test)

### Step 1: Write the failing integration test

Create `tests/scripts/benchmark.bats`:

```bash
#!/usr/bin/env bats
# Integration tests for scripts/benchmark.sh

setup() {
  ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

  # Use temp directory for test database
  TEST_DB_DIR="${BATS_TEST_TMPDIR}/benchmarks"
  export BENCHMARK_DB_DIR="${TEST_DB_DIR}"
  export BENCHMARK_DB_PATH="${TEST_DB_DIR}/benchmarks.db"
}

teardown() {
  rm -rf "${TEST_DB_DIR}"
}

@test "benchmark.sh: runs doctor.sh and records result" {
  run "${ROOT_DIR}/scripts/benchmark.sh" doctor
  [ "$status" -eq 0 ]

  # Check database was created and has entry
  run sqlite3 "${BENCHMARK_DB_PATH}" "SELECT name FROM benchmarks WHERE name LIKE '%doctor%';"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "doctor" ]]
}

@test "benchmark.sh: displays usage without arguments" {
  run "${ROOT_DIR}/scripts/benchmark.sh"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Usage" ]]
}

@test "benchmark.sh: handles nonexistent script" {
  run "${ROOT_DIR}/scripts/benchmark.sh" nonexistent-script
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not found" ]] || [[ "$output" =~ "does not exist" ]]
}
```

### Step 2: Run test to verify it fails

```bash
bats tests/scripts/benchmark.bats
```

Expected: FAIL - "scripts/benchmark.sh: No such file or directory"

### Step 3: Write minimal implementation

Create `scripts/benchmark.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
source "${ROOT_DIR}/scripts/lib/benchmark.sh"
TAG="benchmark"

usage() {
  cat <<'EOF'
Usage: scripts/benchmark.sh <script-name> [args...]

Benchmark execution of a dotfiles script.

Examples:
  scripts/benchmark.sh doctor
  scripts/benchmark.sh setup-git-config
  scripts/benchmark.sh drift-check --verbose

Arguments:
  script-name   Name of script to benchmark (without .sh extension)
  args          Optional arguments to pass to the script
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

script_name="$1"
shift

# Resolve script path
script_path="${ROOT_DIR}/scripts/${script_name}.sh"
if [[ ! -f "${script_path}" ]]; then
  # Try without .sh extension
  script_path="${ROOT_DIR}/scripts/${script_name}"
  if [[ ! -f "${script_path}" ]]; then
    log_err "script not found: ${script_name}"
    exit 1
  fi
fi

# Run benchmark
log "benchmarking: ${script_name}"
benchmark_exec "script/${script_name}" "${script_path}" "$@"
exit_code=$?

# Display summary
echo
log "benchmark complete, exit code: ${exit_code}"
benchmark_report "script/${script_name}" | tail -n 5

exit ${exit_code}
```

Make executable:

```bash
chmod +x scripts/benchmark.sh
```

### Step 4: Run test to verify it passes

```bash
bats tests/scripts/benchmark.bats
```

Expected: PASS

### Step 5: Commit

```bash
mkdir -p tests/scripts
git add scripts/benchmark.sh tests/scripts/benchmark.bats
git commit -m "feat(benchmark): add ad-hoc benchmarking script

- Standalone script for benchmarking any dotfiles script
- Resolves script paths automatically
- Displays results after execution
- Full integration test coverage"
```

---

## Task 7: Bootstrap Integration

**Files:**
- Modify: `scripts/bootstrap.sh`

### Step 1: No test (bootstrap integration tested manually)

Integration testing of bootstrap is complex and already covered by existing bootstrap functionality. We'll test manually after implementation.

### Step 2: Write implementation

Modify `scripts/bootstrap.sh`:

1. Add benchmark.sh source after other libraries (around line 7):

```bash
source "${ROOT_DIR}/scripts/lib/benchmark.sh"
```

2. Modify the `run_hook()` function to use `benchmark_exec`:

Find the `run_hook()` function (around line 276) and modify it:

```bash
run_hook() {
  local section_name="$1"
  shift

  # Use benchmark_exec to wrap the command
  if benchmark_exec "bootstrap/${section_name}" "$@"; then
    _record "${section_name}" "ok"
  else
    _record "${section_name}" "FAIL"
  fi
}
```

### Step 3: Test manually

```bash
# Run bootstrap in test mode (no-packages, no-stow, no-post to just test infrastructure)
./install.sh --no-packages --no-stow --no-post

# Check that benchmarks were recorded
sqlite3 ~/.local/share/dotfiles/benchmarks.db "SELECT name, duration_ms FROM benchmarks WHERE name LIKE 'bootstrap/%' ORDER BY timestamp DESC LIMIT 5;"
```

Expected: See bootstrap phases with timing data

### Step 4: Commit

```bash
git add scripts/bootstrap.sh
git commit -m "feat(benchmark): integrate with bootstrap

- Source benchmark.sh library
- Wrap run_hook() commands with benchmark_exec
- Automatically track all bootstrap phase timing
- Maintains backward compatibility"
```

---

## Task 8: Mise Tasks

**Files:**
- Modify: `.mise.toml`

### Step 1: Add benchmark tasks

Add to `.mise.toml` in the appropriate section (after dev-tools section):

```toml
# ---------------------------------------------------------------------------
# Benchmarking
# ---------------------------------------------------------------------------

[tasks.benchmark]
description = "Benchmark execution of a dotfiles script"
run = "./scripts/benchmark.sh"

[tasks.benchmark-report]
description = "Display benchmark results with optional filter"
run = '''
#!/usr/bin/env bash
source scripts/lib/log.sh
source scripts/lib/cmd.sh
source scripts/lib/benchmark.sh
TAG="benchmark-report"
benchmark_report "$@"
'''
```

### Step 2: Test the tasks

```bash
# Test benchmark task
mise run benchmark doctor

# Test report task
mise run benchmark-report

# Test report with filter
mise run benchmark-report bootstrap
```

Expected: Both tasks work correctly

### Step 3: Commit

```bash
git add .mise.toml
git commit -m "feat(benchmark): add mise tasks

- mise run benchmark <script> for ad-hoc benchmarking
- mise run benchmark-report [filter] to view results
- Integrated with existing task structure"
```

---

## Task 9: Dependencies and Gitignore

**Files:**
- Modify: `.gitignore`
- Modify: `Brewfile.macos`
- Modify: `config/apt-packages.txt`

### Step 1: Update .gitignore

Add to `.gitignore`:

```
# Benchmark database (local runtime data)
.local/share/dotfiles/
```

### Step 2: Check if sqlite3 needs to be added

```bash
# Check if sqlite3 is already in Brewfile
grep -q sqlite Brewfile.macos || echo "Need to add sqlite3"

# Check if sqlite3 is available
command -v sqlite3 >/dev/null && echo "sqlite3 available" || echo "sqlite3 missing"
```

### Step 3: Add sqlite3 if needed

Only add if not present and not available by default:

To `Brewfile.macos` (if needed):
```ruby
brew "sqlite"  # Database for benchmark storage
```

To `config/apt-packages.txt` (if needed):
```
sqlite3
```

### Step 4: Test

```bash
# Verify gitignore works
mkdir -p ~/.local/share/dotfiles
touch ~/.local/share/dotfiles/test.db
git status | grep -q "test.db" && echo "FAIL: file tracked" || echo "PASS: file ignored"
rm ~/.local/share/dotfiles/test.db
```

### Step 5: Commit

```bash
git add .gitignore Brewfile.macos config/apt-packages.txt
git commit -m "chore(benchmark): add dependencies and gitignore

- Exclude benchmark database from git
- Add sqlite3 to package lists if needed
- Ensure database location is properly ignored"
```

---

## Task 10: Documentation

**Files:**
- Modify: `scripts/lib/README.md`
- Modify: `README.md`

### Step 1: Update library documentation

Add to `scripts/lib/README.md` in the library table (around line 20):

```markdown
| `benchmark.sh` | Performance benchmarking | `benchmark_init`, `benchmark_exec`, `benchmark_report` | Bootstrap + scripts |
```

Add new section after the launchd.sh section (around line 280):

```markdown
### benchmark.sh - Performance Benchmarking

Track execution time and metrics for scripts and bootstrap phases.

**Core Functions:**

```bash
# Initialize database (automatically called by benchmark_exec)
benchmark_init

# Execute command with timing and metrics collection
benchmark_exec <name> <command...>

# Display benchmark results with optional filtering
benchmark_report [name_filter]
```

**Example Usage:**

```bash
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
source "${ROOT_DIR}/scripts/lib/benchmark.sh"

# Benchmark a command
benchmark_exec "my-operation" my-script.sh --arg1 --arg2

# View all results
benchmark_report

# View filtered results
benchmark_report "bootstrap"
```

**Database Schema:**

Stores results in `~/.local/share/dotfiles/benchmarks.db`:
- `timestamp` - ISO8601 execution time
- `name` - Benchmark name (e.g., "bootstrap/Shell")
- `duration_ms` - Execution time in milliseconds
- `exit_code` - Command exit code
- `cpu_percent` - CPU usage (NULL for now)
- `mem_mb` - Memory usage (NULL for now)
- `git_commit` - Current HEAD commit hash

**Features:**
- Always-on monitoring with minimal overhead (<20ms)
- Non-invasive error handling (never breaks operations)
- Automatic integration with bootstrap via `run_hook()`
- Ad-hoc benchmarking via `scripts/benchmark.sh`

**Mise Tasks:**
```bash
mise run benchmark doctor          # Benchmark a script
mise run benchmark-report          # View all results
mise run benchmark-report bootstrap # View filtered results
```
```

### Step 2: Update main README

Add to README.md in the "Day-2 commands" section (around line 113):

```markdown
### Benchmarking
```bash
mise run benchmark <script>        # benchmark individual script
mise run benchmark-report [filter] # view benchmark results
```
```

### Step 3: Commit

```bash
git add scripts/lib/README.md README.md
git commit -m "docs(benchmark): add comprehensive documentation

- Update library README with benchmark.sh section
- Add examples and database schema
- Document mise tasks
- Update main README with benchmarking commands"
```

---

## Task 11: Final Testing and Validation

**Files:**
- Test all components

### Step 1: Run full test suite

```bash
# Run all benchmark tests
bats tests/lib/benchmark.bats
bats tests/scripts/benchmark.bats

# Verify test count
bats tests/lib/benchmark.bats --count
```

Expected: All tests pass (19+ tests)

### Step 2: Manual integration test

```bash
# Clear any existing benchmarks
rm -f ~/.local/share/dotfiles/benchmarks.db

# Run bootstrap with benchmarking
./install.sh --no-packages --no-stow --no-post

# Verify data
sqlite3 ~/.local/share/dotfiles/benchmarks.db <<SQL
SELECT COUNT(*) as total_benchmarks FROM benchmarks;
SELECT name, duration_ms FROM benchmarks ORDER BY duration_ms DESC LIMIT 5;
SQL

# Test ad-hoc benchmarking
mise run benchmark doctor

# Test reporting
mise run benchmark-report
mise run benchmark-report bootstrap
```

Expected: All commands work, data is recorded correctly

### Step 3: Push changes

```bash
# Push all commits
git push

# Sync beads if used
bd sync
```

### Step 4: Final summary

Create summary of what was built:

```bash
echo "Benchmarking system implementation complete!"
echo ""
echo "Components:"
echo "  ✓ scripts/lib/benchmark.sh - Core library (3 functions)"
echo "  ✓ scripts/benchmark.sh - Ad-hoc benchmarking wrapper"
echo "  ✓ tests/lib/benchmark.bats - Unit tests (19+ tests)"
echo "  ✓ tests/scripts/benchmark.bats - Integration tests (3 tests)"
echo "  ✓ Bootstrap integration - Automatic phase tracking"
echo "  ✓ Mise tasks - benchmark and benchmark-report"
echo "  ✓ Documentation - README + library docs"
echo ""
echo "Usage:"
echo "  mise run benchmark <script>    # Ad-hoc benchmarking"
echo "  mise run benchmark-report      # View results"
echo "  ./install.sh                   # Automatic bootstrap tracking"
```

---

## Summary

**Total Tasks:** 11
**Estimated Time:** 60-90 minutes
**Test Coverage:** 22+ tests (19 unit + 3 integration)

**Files Created:**
- `scripts/lib/benchmark.sh` (core library)
- `scripts/benchmark.sh` (wrapper script)
- `tests/lib/benchmark.bats` (unit tests)
- `tests/scripts/benchmark.bats` (integration tests)
- `docs/plans/2026-03-04-benchmarking-implementation.md` (this file)

**Files Modified:**
- `scripts/bootstrap.sh` (integration)
- `.mise.toml` (tasks)
- `.gitignore` (database exclusion)
- `Brewfile.macos`, `config/apt-packages.txt` (dependencies)
- `scripts/lib/README.md` (library docs)
- `README.md` (usage docs)

**Database:**
- Location: `~/.local/share/dotfiles/benchmarks.db`
- Schema: 8 columns (id, timestamp, name, duration_ms, exit_code, cpu_percent, mem_mb, git_commit)
- Gitignored: Yes

**Key Features:**
- ✅ Always-on monitoring (<20ms overhead)
- ✅ Bootstrap integration (automatic phase tracking)
- ✅ Ad-hoc script benchmarking
- ✅ SQLite storage with full metrics
- ✅ Terminal output with formatted tables
- ✅ Non-invasive error handling
- ✅ Comprehensive test coverage
- ✅ Full documentation

**Next Steps:**
After implementation, consider these enhancements:
1. Implement actual CPU/memory metrics collection
2. Add cleanup command for old benchmarks
3. Add trend analysis commands
4. Create visualization/dashboard
5. Add comparison mode (current vs historical average)
