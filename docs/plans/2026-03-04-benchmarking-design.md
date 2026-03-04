# Performance Benchmarking System Design

**Date:** 2026-03-04
**Status:** Approved
**Type:** New Feature

## Overview

A comprehensive benchmarking system to measure and track performance of bootstrap phases and individual scripts. Provides always-on monitoring with minimal overhead, storing results in SQLite with full metrics (timing, exit codes, system load, git commit).

## Requirements

- **Comprehensive coverage:** Bootstrap phases + individual scripts
- **Always-on:** Automatic timing collection during normal operations
- **Full metrics:** Time, exit code, CPU/memory usage, git commit hash
- **Dual output:** SQLite database for history + terminal output for immediate feedback
- **Non-invasive:** Never break the underlying operation if benchmarking fails
- **Low overhead:** Target <20ms per benchmark operation

## Architecture

### High-Level Structure

Three-layer architecture:

1. **Library Layer** - `scripts/lib/benchmark.sh`
   - Core benchmarking functions
   - Database management
   - Metrics collection

2. **Integration Layer** - Modified `bootstrap.sh` + new `scripts/benchmark.sh`
   - Bootstrap integration via modified `run_hook()`
   - Ad-hoc script benchmarking via standalone wrapper

3. **Storage Layer** - SQLite database at `~/.local/share/dotfiles/benchmarks.db`
   - Persistent cross-session storage
   - Queryable history
   - No external dependencies

### Control Flow

```
Bootstrap/Script → benchmark_exec → collect start metrics → execute command →
collect end metrics → calculate duration → write to SQLite → display results
```

## Components

### Core Library: `scripts/lib/benchmark.sh`

**Functions:**

1. **`benchmark_init()`**
   - Create database directory if needed
   - Initialize SQLite schema
   - Verify sqlite3 is available
   - Set BENCHMARK_ENABLED flag

2. **`benchmark_exec <name> <command...>`**
   - Ensure database initialized
   - Capture start time (nanosecond precision)
   - Sample system metrics (CPU/memory)
   - Execute command, capture exit code
   - Capture end time, calculate duration
   - Sample metrics again, calculate average
   - Get git commit hash
   - INSERT record into database
   - Return original command exit code

3. **`benchmark_report [name_filter]`**
   - Query database with optional filtering
   - Display formatted table of results
   - Show summary statistics (count, avg, min, max)

### Database Schema

**Table: `benchmarks`**

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PRIMARY KEY | Auto-increment ID |
| timestamp | TEXT | ISO8601 timestamp (YYYY-MM-DDTHH:MM:SS) |
| name | TEXT | Benchmark name (e.g., "bootstrap/Shell", "script/doctor") |
| duration_ms | INTEGER | Execution time in milliseconds |
| exit_code | INTEGER | Command exit code |
| cpu_percent | REAL | Approximate CPU usage percentage |
| mem_mb | REAL | Peak memory usage in megabytes |
| git_commit | TEXT | Current HEAD commit hash |

**Location:** `~/.local/share/dotfiles/benchmarks.db` (XDG data dir, gitignored)

### Integration Points

1. **Bootstrap Integration (`bootstrap.sh`):**
   - Source `scripts/lib/benchmark.sh`
   - Modify `run_hook()` to wrap commands with `benchmark_exec "bootstrap/${section_name}" <command>`
   - Maintains backward compatibility (original exit codes preserved)

2. **Ad-hoc Benchmarking (`scripts/benchmark.sh`):**
   - New standalone script for benchmarking any script
   - Usage: `./scripts/benchmark.sh <script-name>`
   - Resolves script path, calls `benchmark_exec "script/<name>" <path>`

3. **Mise Tasks:**
   - `mise run benchmark <script>` - Benchmark individual script
   - `mise run benchmark-report [filter]` - Display results

## Data Flow

### Bootstrap Integration Flow

```
bootstrap.sh calls run_hook "Shell" setup-git-config.sh
  ↓
run_hook sources benchmark.sh, calls benchmark_exec "bootstrap/Shell" setup-git-config.sh
  ↓
benchmark_exec records: start_time, cpu_before, mem_before
  ↓
Executes setup-git-config.sh
  ↓
benchmark_exec records: end_time, cpu_after, mem_after, exit_code, git_commit
  ↓
Calculates duration_ms = (end_time - start_time) / 1000000
  ↓
Inserts into SQLite: (timestamp, name, duration_ms, exit_code, cpu%, mem_mb, git_commit)
  ↓
Returns original exit_code to bootstrap
```

### Ad-hoc Script Benchmarking Flow

```
User runs: mise run benchmark doctor
  ↓
Calls: scripts/benchmark.sh doctor
  ↓
Resolves to: scripts/doctor.sh
  ↓
Calls: benchmark_exec "script/doctor" ./scripts/doctor.sh
  ↓
Same collection flow as bootstrap
  ↓
Displays result to terminal
```

### Metrics Collection Strategy

- **Time:** Use `date +%s%N` (nanosecond precision on Linux) or `gdate` on macOS (from coreutils)
- **CPU/Memory:** Sample process tree metrics via `ps` before/after execution, calculate average
- **Git Commit:** One-time call to `git rev-parse HEAD` from dotfiles root
- **Overhead:** Target <20ms per benchmark call (mostly SQLite write time)

### Terminal Output

After each `benchmark_exec`, print one-line summary:
```
✓ bootstrap/Shell completed in 1.2s
```

## Error Handling

**Core Principle:** Benchmarking must never break the underlying operation.

### Failure Scenarios

1. **Database Failures:**
   - If SQLite unavailable or database creation fails: log warning, set `BENCHMARK_ENABLED=0`, continue
   - Original command still executes normally

2. **Metrics Collection Failures:**
   - If `date +%s%N` unavailable: fall back to `date +%s` (second precision)
   - If `ps` fails to get metrics: record as NULL in database
   - If git rev-parse fails: record commit as "unknown"
   - None of these stop execution

3. **Command Exit Code Preservation:**
   - Always capture and return original command's exit code
   - Use `set +e` around benchmarked command to prevent pipefail issues
   - Re-enable `set -e` after capturing exit code

4. **Disk Space:**
   - Database grows ~100 bytes per entry (~10KB per 100 benchmarks)
   - No automatic cleanup (keep full history)
   - Future enhancement: cleanup command for old records

5. **Concurrency:**
   - SQLite handles concurrent writes automatically
   - No additional locking needed

6. **Missing Dependencies:**
   - Check for `sqlite3` via `require_cmd` during `benchmark_init`
   - If missing: disable benchmarking with clear warning
   - Consider adding sqlite3 to Brewfile/apt-packages

## Testing Strategy

### Unit Tests (`tests/lib/benchmark.bats`)

1. **Database Initialization:**
   - Creates database file in temp directory
   - Schema created with all required columns
   - Idempotent (re-running doesn't error)

2. **Execution & Timing:**
   - Runs command successfully
   - Returns original command exit code (success and failure cases)
   - Duration is captured correctly (test with `sleep 0.1`)
   - Database record created with correct name

3. **Metrics Collection:**
   - Git commit hash captured (or "unknown" outside repo)
   - Exit code recorded correctly
   - CPU/memory fields accept NULL on collection failure
   - Timestamp in ISO8601 format

4. **Report Function:**
   - Displays all records
   - Filtering by name pattern works
   - Summary statistics calculated correctly
   - Handles empty database gracefully

5. **Error Handling:**
   - Continues if SQLite unavailable
   - Continues if metrics collection fails
   - Original command exit code always preserved

6. **Integration Test:**
   - Full workflow: init → exec → report
   - Data persists across function calls

### Manual Testing

- Run bootstrap with benchmarking, verify all phases recorded
- Use `mise run benchmark doctor` for ad-hoc testing
- Query database directly with `sqlite3` to verify data integrity
- Test on both macOS and Linux (CI catches platform issues)

### Test Database Location

Use `$BATS_TEST_TMPDIR` for isolated test databases per test run.

## Implementation Notes

### Dependencies

- **sqlite3** - Required for database operations (add to Brewfile/apt-packages)
- **coreutils** - For `gdate` on macOS (already in Nix flake)
- **ps** - Standard utility for process metrics (always available)

### Compatibility

- **macOS:** Use `gdate` from coreutils for nanosecond precision
- **Linux:** Use built-in `date +%s%N`
- **Both:** Graceful fallback to second precision if needed

### Future Enhancements

- Cleanup command: `mise run benchmark-clean --older-than 90d`
- Trend analysis: `mise run benchmark-trends <name>` to show performance over time
- Comparison mode: Compare current run against historical average
- Export to JSON/CSV for external analysis
- Web dashboard for visualization

## Success Criteria

- ✅ Bootstrap automatically tracks timing for all phases
- ✅ Individual scripts can be benchmarked ad-hoc
- ✅ Results stored in SQLite with full metrics
- ✅ Terminal output shows immediate feedback
- ✅ Zero impact on operations if benchmarking fails
- ✅ Overhead <20ms per benchmark operation
- ✅ 100% test coverage for benchmark.sh library

## Files to Create/Modify

**New Files:**
- `scripts/lib/benchmark.sh` - Core benchmarking library
- `scripts/benchmark.sh` - Ad-hoc benchmarking wrapper script
- `tests/lib/benchmark.bats` - Comprehensive test suite
- `docs/plans/2026-03-04-benchmarking-design.md` - This document

**Modified Files:**
- `scripts/bootstrap.sh` - Integrate benchmark_exec into run_hook()
- `.mise.toml` - Add benchmark and benchmark-report tasks
- `.gitignore` - Exclude benchmarks database
- `Brewfile.macos` / `config/apt-packages.txt` - Add sqlite3 if needed

**Database File (gitignored):**
- `~/.local/share/dotfiles/benchmarks.db`
