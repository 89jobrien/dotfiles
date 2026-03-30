# Scripts Architecture

Comprehensive documentation for the dotfiles `scripts/` directory structure, conventions, and architecture.

## Overview

The scripts directory contains bootstrap automation, maintenance utilities, and shared libraries following a layered architecture with consistent patterns across all scripts.

```text
scripts/
├── lib/                    # Shared libraries (cmd, dryrun, json, log, pkg)
├── bootstrap.sh            # Main bootstrap orchestrator
├── setup-*.sh              # Post-bootstrap setup scripts
├── *-dev.sh                # Development environment scripts
├── *-service.sh            # LaunchDaemon/systemd service managers
├── *.sh                    # Utility scripts (doctor, etc.)
└── *.rs / *.py             # Rust/Python standalone scripts (run via rust-script / uv)
```

## Architecture Layers

### Layer 1: Shared Libraries (`scripts/lib/`)

Foundation layer providing reusable utilities for all scripts:

| Library      | Purpose                  | Functions                                                              |
| ------------ | ------------------------ | ---------------------------------------------------------------------- |
| `log.sh`     | Logging & output         | `log`, `log_ok`, `log_warn`, `log_err`, `section`, `spin`              |
| `cmd.sh`     | Command checking         | `has_cmd`, `require_cmd`, `check_cmd`, `ensure_cmd`                    |
| `pkg.sh`     | Package managers         | `detect_pkg_manager`, `ensure_homebrew`, `bundle_install`              |
| `dryrun.sh`  | Dry-run mode             | `set_dryrun_mode`, `is_dryrun`, `dryrun_exec`                          |
| `json.sh`    | JSON manipulation        | `merge_json_config`, `read_json_value`, `validate_json`                |
| `launchd.sh` | macOS services (launchd) | `launchd_is_loaded`, `launchd_start`, `launchd_stop`, `launchd_status` |

**Design Principles:**

- Single responsibility per library
- No interdependencies (except log.sh dependency)
- Comprehensive test coverage (82 bats tests)
- Clear function naming conventions

See [`scripts/lib/README.md`](scripts/lib/README.md) for detailed library documentation.

### Layer 2: Bootstrap Scripts

Entry points and orchestration:

| Script              | Purpose                                                       | Layer      |
| ------------------- | ------------------------------------------------------------- | ---------- |
| `bootstrap.sh`      | Main orchestrator - runs package install, stow, post-hooks    | Bootstrap  |
| `install.sh` (root) | Entry point - delegates to `pj dot install` or `bootstrap.sh` | Entry      |
| `drift-check.sh`    | Detect uncommitted changes & stow conflicts                   | Validation |
| `doctor.sh`         | Validate required tools are installed                         | Validation |

**Bootstrap Flow:**

1. `install.sh` → `pj dot install` → `bootstrap.sh`
2. Zerobrew/Homebrew package installation
3. Mise runtime installation
4. Stow symlink creation
5. Post-hook execution (ordered sections)
6. Summary report

### Layer 3: Setup Scripts (`setup-*.sh`)

Post-bootstrap configuration scripts run by `bootstrap.sh`:

| Script                     | Purpose                                     | Hook Section    |
| -------------------------- | ------------------------------------------- | --------------- |
| `setup-git-config.sh`      | Git configuration                           | Shell           |
| `setup-oh-my-zsh.sh`       | Oh My Zsh installation                      | Shell           |
| `setup-secrets.sh`         | SOPS secret decryption                      | Secrets         |
| `setup-nix.sh`             | Nix installation & flake packages           | Nix             |
| `setup-macos.sh`           | macOS defaults & Raycast scripts            | macOS           |
| `setup-ai-tools.sh`        | AI tool configs (Claude, Cursor, Zed, etc.) | AI Tools        |
| `setup-maestro.sh`         | Maestro project setup                       | Maestro         |
| `setup-companion-repos.sh` | Clone companion projects                    | Companion Repos |
| `setup-dev-tools.sh`       | Cargo/Bun tool installation                 | Dev Tools       |
| `setup-nvchad-avante.sh`   | Neovim configuration                        | Editor          |
| `setup-zerobrew.sh`        | Zerobrew installation (pre-hook)            | Pre-Homebrew    |

**Conventions:**

- Exit 0 on skip (not failure) to allow bootstrap to continue
- Use `log_skip` for non-critical missing dependencies
- Source required libraries (log.sh, cmd.sh, etc.)
- Set `TAG` variable for logging

### Layer 4: Development Scripts (`*-dev.sh`)

Development environment management:

| Script             | Purpose                                | Dependencies           |
| ------------------ | -------------------------------------- | ---------------------- |
| `compose-dev.sh`   | Docker Compose development environment | docker, docker-compose |
| `container-dev.sh` | Container runtime management (colima)  | colima, docker         |
| `maestro-dev.sh`   | Maestro project development workflow   | make, git              |
| `observe-dev.sh`   | Observability stack (Vector, etc.)     | docker-compose         |

### Layer 5: Service Scripts (`*-service.sh`)

LaunchDaemon/systemd service managers:

| Script                        | Purpose                      | Platform        |
| ----------------------------- | ---------------------------- | --------------- |
| `vector-service.sh`           | Vector log collection daemon | macOS (launchd) |
| `rust-clean-service.sh`       | Rust artifact cleanup daemon | macOS (launchd) |
| `vector-retention-service.sh` | Log retention cleanup        | macOS (launchd) |
| `claude-log-retention.sh`     | Claude log cleanup           | Cross-platform  |

**Service Commands:**

- `install` - Write plist and bootstrap service
- `uninstall` - Stop and remove service
- `start/stop/restart` - Service control
- `status` - Check service state
- `logs` - Tail service logs

### Layer 6: Utility Scripts

Standalone utilities:

| Script          | Purpose                                         |
| --------------- | ----------------------------------------------- |
| `rust-clean.sh` | Manual Rust artifact cleanup (uses cargo-sweep) |

## Script Conventions

All scripts follow these conventions established during refactoring:

### 1. Standard Header

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
# ... other libraries as needed
TAG="script-name"
```

**Flags:**

- `set -e` - Exit on error
- `set -u` - Error on undefined variables
- `set -o pipefail` - Catch errors in pipes

### 2. Library Usage

**Always source in order:**

1. `log.sh` - Required first (other libraries may log)
2. `cmd.sh` - Command checking
3. `pkg.sh` - Package managers (if needed)
4. `dryrun.sh` - Dry-run mode (if needed)
5. `json.sh` - JSON manipulation (if needed)

### 3. Logging

Use library functions instead of echo:

```bash
log "info message"           # Info
log_ok "success message"     # Success (green)
log_warn "warning message"   # Warning (yellow)
log_err "error message"      # Error (red)
log_skip "skipped operation" # Skip (gray)
section "Section Name"       # Section header
```

### 4. Command Checking

Use library functions instead of inline `command -v`:

```bash
# Silent check
if has_cmd docker; then
  # ...
fi

# Required command (exits if missing)
require_cmd git "brew install git"

# Health check (sets status variable)
status=0
check_cmd jq status
check_optional_cmd gum

# Install if missing
ensure_cmd bacon "cargo install --locked bacon" failed
```

### 5. Error Handling

**Post-hook scripts:**

- Exit 0 on skip to allow bootstrap to continue
- Exit 1 only for critical errors
- Use `log_skip` for non-critical missing dependencies

**Service scripts:**

- Exit 1 for errors
- Use `|| true` for non-critical failures in service management

**Utility scripts:**

- Exit 1 for errors
- Provide clear error messages with `log_err`

### 6. Dry-Run Support

For destructive operations:

```bash
source "${ROOT_DIR}/scripts/lib/dryrun.sh"

# Parse args
case "$1" in
  --dry-run) set_dryrun_mode 1 ;;
esac

# Conditional execution
dryrun_exec rm -rf /tmp/cache
dryrun_exec docker system prune -af
```

## Migration Status

### Completed Migrations

| Migration          | Status  | Scripts                                |
| ------------------ | ------- | -------------------------------------- |
| log.sh adoption    | ✅ 100% | All scripts use standardized logging   |
| cmd.sh adoption    | ✅ 100% | 21 scripts use shared command checking |
| pkg.sh adoption    | ✅ Done | setup-ai-tools.sh, bootstrap.sh        |
| json.sh adoption   | ✅ Done | setup-ai-tools.sh                      |
| dryrun.sh adoption | ✅ Done | setup-maestro.sh, rust-clean.sh, etc.  |

### Test Coverage

All shared libraries have comprehensive bats test coverage:

- ✅ cmd.sh - 20 tests
- ✅ dryrun.sh - 19 tests
- ✅ json.sh - 25 tests
- ✅ pkg.sh - 18 tests
- ✅ launchd.sh - 20 tests
- **Total: 102 passing tests**

Run tests: `bats tests/lib/*.bats` or `mise run test-lib`

## Directory Structure

```text
scripts/
├── lib/                          # Shared libraries
│   ├── README.md                 # Library documentation
│   ├── cmd.sh                    # Command checking utilities
│   ├── dryrun.sh                 # Dry-run mode handling
│   ├── json.sh                   # JSON manipulation
│   ├── launchd.sh                # macOS service management (launchd)
│   ├── log.sh                    # Logging functions
│   └── pkg.sh                    # Package manager detection
│
├── bootstrap.sh                  # Main bootstrap orchestrator
├── install.sh → (root)           # Entry point (symlinked from root)
│
├── setup-*.sh                    # Post-bootstrap setup scripts
│   ├── setup-git-config.sh       # Git configuration
│   ├── setup-oh-my-zsh.sh        # Oh My Zsh setup
│   ├── setup-secrets.sh          # SOPS secret decryption
│   ├── setup-nix.sh              # Nix package manager
│   ├── setup-macos.sh            # macOS defaults
│   ├── setup-ai-tools.sh         # AI tool configurations
│   ├── setup-maestro.sh          # Maestro project setup
│   ├── setup-companion-repos.sh  # Clone companion repos
│   ├── setup-dev-tools.sh        # Dev tool installation
│   ├── setup-nvchad-avante.sh    # Neovim config
│   └── setup-zerobrew.sh         # Zerobrew installation
│
├── *-dev.sh                      # Development scripts
│   ├── compose-dev.sh            # Docker Compose dev env
│   ├── container-dev.sh          # Container runtime mgmt
│   ├── maestro-dev.sh            # Maestro workflow
│   └── observe-dev.sh            # Observability stack
│
├── *-service.sh                  # Service managers
│   ├── vector-service.sh         # Vector daemon
│   ├── rust-clean-service.sh     # Rust cleanup daemon
│   └── vector-retention-service.sh # Log retention
│
├── claude-log-retention.sh       # Claude log cleanup
├── doctor.sh                     # System health check
├── drift-check.sh                # Detect uncommitted changes
├── rust-clean.sh                 # Manual Rust cleanup
│
└── post-bootstrap.local.example.sh  # Local customization template
```

## Adding New Scripts

When creating a new script:

1. **Use the standard header** (see Script Conventions)
2. **Source required libraries** in order (log.sh first)
3. **Set TAG variable** before any log calls
4. **Follow naming conventions:**
   - `setup-*.sh` for bootstrap post-hooks
   - `*-dev.sh` for development workflows
   - `*-service.sh` for daemon managers
   - Descriptive names for utilities
5. **Add to bootstrap** if it's a post-hook:
   - Add `run_hook` call in `bootstrap.sh`
   - Add mise task in `.mise.toml`
   - Add recipe in `Justfile`
6. **Add tests** if introducing new patterns
7. **Update documentation** (this file and README.md)

### Template

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/log.sh"
source "${ROOT_DIR}/scripts/lib/cmd.sh"
TAG="my-script"

# Require critical dependencies
require_cmd jq "brew install jq"

# Optional dependency checking
if ! has_cmd gum; then
  log_skip "gum not available; using plain output"
fi

main() {
  section "My Script"
  log "Starting operation..."

  # Your logic here

  log_ok "Operation complete"
}

main "$@"
```

## Related Documentation

- [`scripts/lib/README.md`](scripts/lib/README.md) - Detailed library reference
- [`tests/README.md`](tests/README.md) - Test suite documentation
- [`CLAUDE.md`](CLAUDE.md) - High-level dotfiles architecture
- [`.mise.toml`](.mise.toml) - Task definitions
- [`Justfile`](Justfile) - Automation recipes

## Maintenance

### Adding New Libraries

When creating new shared libraries:

1. Create `scripts/lib/newlib.sh` with clear function documentation
2. Add comprehensive bats tests in `tests/lib/newlib.bats`
3. Document in `scripts/lib/README.md`
4. Update this document's Layer 1 table
5. Add migration guide if replacing inline patterns

### Refactoring

When refactoring scripts to use new patterns:

1. Verify existing functionality first
2. Update one pattern at a time
3. Test after each change (`bash -n script.sh`)
4. Run comprehensive tests (`mise run test`)
5. Update documentation
6. Commit with descriptive message

### Quality Standards

All scripts must:

- Pass shellcheck (or document exceptions)
- Follow consistent style (see Conventions)
- Use shared libraries (no duplicate code)
- Have clear error messages
- Document non-obvious behavior
- Use proper exit codes

---

## Rust Scripts (`scripts/*.rs`) and Python Scripts (`scripts/*.py`)

Standalone scripts run via `rust-script` or `uv run`. These are the **canonical** implementations — any `.sh` equivalents are legacy.

Each `.rs` file embeds its own `[dependencies]` in a `//! ```cargo` block (PEP 723-style for Rust). Each `.py` file uses a `# /// script` block for `uv run`.

### Execution Contract

| Script | Runner | Mise task | Env vars | Log output |
|--------|--------|-----------|----------|------------|
| `drift-check.rs` | `rust-script` | `mise run drift` | none | stderr |
| `system-health.rs` | `rust-script` | `mise run health [summary\|live\|procs\|disk]` | none | stdout |
| `check-updates.rs` | `rust-script` | `mise run update-check` | `INFRA_DOTFILES_ROOT`, `DOTFILES_CHECK_CACHE` (optional) | stderr |
| `rust-clean.rs` | `rust-script` | `mise run rust-clean [--dry-run]` | `RUST_CLEAN_DIR` (default: `$HOME/dev`), `RUST_CLEAN_DAYS` (default: 14), `DRY_RUN` | stderr |
| `redact-audit.rs` | `rust-script` | `mise run redact-audit [--verbose]` | none | JSONL → `.logs/redact-audit.jsonl`, findings to stderr with `--verbose` |
| `claude-sessions.rs` | `rust-script` | `mise run logs-sessions\|logs-tools\|logs-agents` | `INFRA_VECTOR_LOG_ROOT` (default: `~/logs/ai/vector`) | stdout table |
| `claude-session-notes.py` | `uv run` | `mise run logs-session-notes` | none | writes to `$VAULT/03_Area-Systems/claude-sessions/` |

### Architecture Pattern

All `.rs` scripts follow hexagonal architecture:

```
Domain layer (pure logic, generic over traits)
  ↑
Ports (traits: Reporter, Sweeper, GitChecker, etc.)
  ↑
Adapters (structs implementing traits via real OS/process calls)
  ↑
Composition root (main() wires adapters + calls domain)
```

Tests use in-process stubs (`StubSweeper`, `CapturingReporter`, etc.) — no subprocess mocking, no filesystem side effects.

### Adding a New Rust Script

1. Create `scripts/myscript.rs` with shebang `#!/usr/bin/env rust-script` and `//! ```cargo` manifest block
2. Define ports as traits, domain logic generic over them, adapters as structs
3. Write tests in `#[cfg(test)]` using stub implementations — run with `rust-script --test scripts/myscript.rs`
4. Add a `[tasks.mytask]` entry to `.mise.toml` and matching recipe to `Justfile`
5. Update the execution contract table above
