# Dotfiles

[![CI](https://github.com/89jobrien/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/89jobrien/dotfiles/actions/workflows/ci.yml)

Reproducible dev environment bootstrap with a managed (immutable) core and local (mutable) overrides.

## Quick start

```bash
cd ~/dotfiles
pj dot install
```

Or from anywhere:

```bash
pj dot install
```

Without `pj`:

```bash
ALLOW_DIRECT_DOTFILES_INSTALL=1 ./install.sh
```

### Task Runners

Three equivalent interfaces for day-2 operations:
- **Human workflow**: `mise run <task>` (interactive, colored output)
- **AI/automation**: `just <recipe>` (scriptable, agent-friendly)
- **Compatibility**: `make <target>` (legacy wrapper)

All task definitions live in `.mise.toml`, `Justfile`, and `Makefile` respectively.

### Testing & Validation

```bash
mise run test              # run all tests
mise run test-lib          # run library tests only
mise run doctor            # validate required tools
mise run drift             # detect uncommitted changes
```

### Project Status

**Testing Infrastructure:**
- 102 automated tests across 5 library test suites (bats framework)
- Continuous integration via GitHub Actions (minimal + comprehensive workflows)
- Cross-platform testing (Ubuntu, macOS)
- Comprehensive test coverage for all shared script libraries

**Recent Activity:**
- Phase 2 script migrations completed (command checking, dry-run standardization)
- launchd.sh library extracted and tested (macOS service management)
- Comprehensive library documentation added (`scripts/lib/README.md`, `SCRIPTS.md`)
- CI/CD workflows established with fast and comprehensive testing pipelines
- See `docs/2026-02-27-bootstrap-runbook.md` for last bootstrap execution log

## What bootstrap does

Bootstrap (`install.sh` → `scripts/bootstrap.sh`) executes in order:

1. `setup-zerobrew.sh` - Install zerobrew (`zb`) as a fast companion to Homebrew
2. Package installation:
   - `zerobrew` (`zb bundle`) when available, fallback to `brew bundle`
   - Platform-specific Brewfiles: `Brewfile.macos` on macOS, `Brewfile.linux` on Linux
   - Falls back to `apt` on Linux if Homebrew unavailable (`config/apt-packages.txt`)
3. `mise install` - Language runtimes (`node`, `bun`, `python`, `uv`, `go`, `rust@1.91`) to avoid version drift
4. Stow symlinks - Default managed packages from `config/stow-packages.txt`
5. Post-setup hooks (ordered by section):
   - **Shell**: `setup-git-config.sh`, `setup-oh-my-zsh.sh`
   - **Secrets**: `setup-secrets.sh` (decrypt + pre-commit policy)
   - **Nix**: `setup-nix.sh` (install Nix + flake packages)
   - **macOS**: `setup-macos.sh` (Alacritty handlers + Raycast scripts)
   - **AI Tools**: `setup-ai-tools.sh` (personal-mcp + all AI tool configs)
   - **Companion Repos**: `setup-companion-repos.sh` (clone personal-mcp, dumcp)
   - **Dev Tools**: `setup-dev-tools.sh` (Rust/Python CLI tooling via cargo/bunx)
   - **Editor**: `setup-nvchad-avante.sh` (Neovim + NvChad + Avante)
   - **Local**: `post-bootstrap.local.sh` (optional, gitignored)
6. Summary table - Shows success/skip/fail status for each phase

## Managed vs local

### Managed (committed, immutable)
Core configuration tracked in git:
- `config/stow-packages.txt` - Default stow packages
- `Brewfile.macos`, `Brewfile.linux` - Platform-specific packages
- `.mise.toml` - Language runtimes + task definitions
- Dotfile package directories: `git/`, `zsh/`, `fish/`, `alacritty/`, `zed/`, etc.
- Bootstrap scripts in `scripts/`

### Local (gitignored, mutable)
Machine-specific overrides and secrets:
- `config/stow-packages.local.txt` - Additional stow packages (copy from `.example`)
- `config/apt-packages.local.txt` - Additional apt packages (copy from `.example`)
- `mise.local.toml` - Local env vars + runtime overrides (copy from `.example`)
- `scripts/post-bootstrap.local.sh` - Custom post-hook (copy from `.example`)
- `~/.zshrc.local` - Shell customizations (auto-sourced by `zsh/.zshrc`)
- Local app state packages: `raycast/`, `mcpm/`, `vector/` (opt-in via local stow list)

## Day-2 commands

Three equivalent task runners:
- `mise run <task>` - Interactive human workflow (preferred)
- `just <recipe>` - Automation/agent workflow
- `make <target>` - Compatibility wrapper

### Core Operations
```bash
mise run doctor            # validate required tools
mise run drift             # detect uncommitted changes + stow conflicts
mise run stow              # restow managed config only
mise run post              # rerun post-setup hooks only
mise run test              # run all tests
mise run test-lib          # run library tests only
```

### Container & K8s
```bash
mise run up                     # start container runtime + k3d + doctor
mise run container-start        # start colima
mise run container-status       # check colima status
mise run compose-up            # start dev container
mise run compose-status        # check compose services
mise run k3d-up                # start k3d cluster (or: kind-up)
mise run tilt-up               # start Tilt dev environment
```

### Observability
```bash
mise run observe                # one-shot summary (runtime + pods + containers)
mise run observe-k8s            # open k9s UI
mise run observe-logs           # tail all k8s logs with stern
mise run observe-docker         # live-refresh docker ps
mise run observe-docker-events  # stream docker events
mise run observe-docker-stats   # stream docker stats
mise run health                 # system summary (cpu/mem/disk/procs)
mise run health-live            # interactive monitor
```

### AI Tools & Integrations
```bash
mise run ai-tools          # full AI tools setup (personal-mcp + configs)
mise run personal-mcp      # install + wire personal MCP
mise run ai-config         # seed/merge Claude/OpenCode/Codex/Gemini configs
mise run raycast-scripts   # link managed raycast script commands (macOS)
```

### Nix & Package Management
```bash
mise run nix-install       # install Nix + flake packages
mise run nix-update        # update nixpkgs lock + reinstall
mise run nix-check         # verify Nix profile + flake
```

### Development Tools
```bash
mise run dev-tools         # install Rust/Python CLI tooling
mise run toolz-install     # install local toolz CLI to ~/.local/bin/toolz
mise run toolz-dev         # build toolz in-place for iteration
mise run nvim              # rerun NvChad + Avante setup
mise run secrets-check     # verify no plaintext secrets staged
mise run companion-repos   # clone personal-mcp, dumcp
```

### From Outside Repo
```bash
# Manual commands from ~
make -C ~/dotfiles observe
make -C ~/dotfiles observe-k8s
make -C ~/dotfiles doctor

# Automation/agents (in repo)
just up
just doctor
just observe-k8s
```

## Script Architecture

The dotfiles use a layered architecture with shared libraries and consistent conventions:

### Shared Libraries (`scripts/lib/`)

Foundation layer providing reusable utilities for all scripts:

| Library | Purpose | Key Functions | Adoption |
|---------|---------|---------------|----------|
| `log.sh` | Logging & output | `log`, `log_ok`, `log_warn`, `log_err`, `section`, `spin` | 100% (all scripts) |
| `cmd.sh` | Command checking | `has_cmd`, `require_cmd`, `check_cmd`, `ensure_cmd` | 21 scripts |
| `pkg.sh` | Package managers | `detect_pkg_manager`, `ensure_homebrew`, `bundle_install` | Core scripts |
| `dryrun.sh` | Dry-run mode | `set_dryrun_mode`, `is_dryrun`, `dryrun_exec` | 3 scripts |
| `json.sh` | JSON manipulation | `merge_json_config`, `read_json_value`, `validate_json` | AI tools |
| `launchd.sh` | macOS services | `launchd_start`, `launchd_stop`, `launchd_status`, `launchd_logs` | 3 service scripts |

**Design Principles:**
- Single responsibility per library
- No interdependencies (except log.sh)
- Comprehensive test coverage (102 tests)
- Clear function naming conventions

**Script Conventions:**
- Standard header with `set -euo pipefail`
- Source libraries in dependency order (log.sh first)
- Set `TAG` variable for logging context
- Use library functions instead of inline code

See `scripts/lib/README.md` and `SCRIPTS.md` for comprehensive documentation.

### Testing Infrastructure

Comprehensive test coverage using bats framework:

```bash
# Run all tests
mise run test

# Run only library tests
mise run test-lib

# Run specific test suite
bats tests/lib/cmd.bats      # 20 tests - command checking
bats tests/lib/dryrun.bats   # 19 tests - dry-run mode
bats tests/lib/json.bats     # 25 tests - JSON manipulation
bats tests/lib/pkg.bats      # 18 tests - package manager detection
bats tests/lib/launchd.bats  # 20 tests - macOS service management
```

**Test Coverage:**
- 102 total tests across 5 library test suites
- 100% coverage of all shared script libraries
- Multi-platform support (Linux + macOS)
- Platform-aware tests (macOS-specific tests skip on Linux)

**CI/CD Workflows:**
- Minimal CI (`.github/workflows/ci.yml`) - Fast syntax checks and core tests on every push/PR
- Comprehensive tests (`.github/workflows/comprehensive.yml`) - Full test suite on schedule/manual trigger
- Cross-platform testing (Ubuntu + macOS)
- Shellcheck integration and coverage analysis

See `tests/README.md` for testing documentation and `.github/workflows/README.md` for CI/CD details.

## Companion projects

These projects live outside the dotfiles repo but depend on tools the dotfiles provide:

| Project | Path | Repo | Language | Tools from dotfiles |
|---------|------|------|----------|---------------------|
| personal-mcp | `~/dev/personal-mcp` | `89jobrien/personal-mcp` | Rust | `cargo`/`rust` (mise), `baml-cli` (dev-tools), `jq`, `just` (nix) |
| dumcp | `~/dev/dumcp` | `89jobrien/dumcp` | Go | `go` (mise) |
| maestro-dev | `~/maestro-dev` | `89jobrien/maestro-dev` | Shell/Docker | `docker`/`colima` (brew), `tmux`, `just` (nix) |

All three are private repos. Bootstrap clones them via `scripts/setup-companion-repos.sh` during the Companion Repos post-hook phase.

Runtime toolchains (Go, Rust) are managed by mise. CLI tools (`just`, `jq`, `tmux`, etc.) come from the Nix flake. Container tooling (`docker`, `colima`) stays in Homebrew.

## Nix packages

Declarative CLI tools layer using a Nix flake (`flake.nix`). Installs a single `buildEnv` profile entry bundling ~30 CLI tools via `nix profile install .#default`. The setup script (`scripts/setup-nix.sh`) installs Nix itself (Determinate Systems installer) then installs or upgrades the profile. Runs as a bootstrap post-hook after Secrets.

```bash
# First-time install (installs Nix + flake packages)
mise run nix-install

# Update nixpkgs pin and reinstall
mise run nix-update

# Verify installation
mise run nix-check
```

### Managing packages

The package list lives in `flake.nix` under `cliPackages`. To add a tool:

1. Find the nixpkgs attribute name: `nix search nixpkgs <term>`
2. Add it to the `cliPackages` list in `flake.nix`
3. Apply: `mise run nix-install`

To see what's currently installed:

```bash
# Show the profile entry
nix profile list

# List all individual tool binaries
ls ~/.nix-profile/bin/
```

### What stays in Brew

- GUI casks (Raycast, Zed, Warp, GitHub Desktop, Codex, Claude Code)
- macOS container stack (colima, docker, docker-buildx, docker-compose)
- macOS-only tools (duti)
- Tools not in nixpkgs (opencode, gemini-cli, git-flow-next)
- Rust devtools via cargo/mise (bacon, cargo-nextest, cargo-watch)
- Language runtimes managed by mise

Packages in both Brew and Nix during transition are safe because `~/.nix-profile/bin`
is typically earlier in PATH. Brewfile entries tagged `# [nix-batch-1]` are the first
migration wave.

### Uninstalling Nix

```bash
/nix/nix-installer uninstall
```

## Dev container

This repo includes a VS Code/Cursor compatible dev container in `.devcontainer/`.

To use it:

```bash
code ~/dotfiles
# then run: "Dev Containers: Reopen in Container"
```

Compose service:

```bash
mise run compose-up
mise run compose-status
mise run compose-logs
```

## Secrets automation

Bootstrap supports encrypted secrets with `sops + age`:

1. Generate/import age key on each machine:
```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

2. Get your public recipient:
```bash
grep '^# public key:' ~/.config/sops/age/keys.txt | cut -d' ' -f4
```

3. Create encrypted dotenv file in repo:
```bash
cp secrets/bootstrap.env.example /tmp/bootstrap.env
# edit /tmp/bootstrap.env with real values
sops --encrypt --input-type dotenv --output-type dotenv \
  --age "<age-public-key>" /tmp/bootstrap.env > secrets/bootstrap.env.sops
rm /tmp/bootstrap.env
```

4. Run bootstrap:
```bash
pj dot install
```

This decrypts to `~/.config/dev-bootstrap/secrets.env` (chmod 600), and `zsh/.zshrc` auto-loads it for new shells.

## Secret policy (dotfiles)

- Dotfiles policy is strict: no plaintext secrets in git history.
- Bootstrap installs a local dotfiles pre-commit hook (`.githooks/pre-commit`) that blocks:
  - staged plaintext secret files (`.env`, `.env.local`, `mise.local.toml`, `secrets/.env.json`, `secrets/bootstrap.env`)
  - staged lines that look like plaintext secret assignments (`token=`, `api_key=`, `password=`, etc.)
- Optional second gate (if `pj` exists): `pj secret scan --staged`.
- Manual check:
```bash
mise run secrets-check
```

## Mise env + secrets pattern

`mise` manages both environment variables and language runtimes without committing secrets:

### Configuration Layers
- **Committed config** (`.mise.toml`):
  - Language runtimes: `node`, `bun`, `python`, `uv`, `go`, `rust@1.91`
  - Env file loading: `[".env", ".env.local", "secrets/.env.json", "secrets/.env.sops.json"]`
  - PATH extensions for project bins
  - Auto-creates `.venv` for Python workflows
  - Sets `pj` TUI defaults (`PJ_TUI_EVENT_STREAM=app`, `PJ_TUI_EVENT_MAX_CHARS=140`)
  - Task definitions for the entire workflow (50+ tasks)

- **Local overrides** (`mise.local.toml`, gitignored):
  - Copy from `mise.local.toml.example`
  - Use `__SECRET_*` keys for masked `mise env` output
  - Override `PJ_TUI_EVENT_STREAM`:
    - `off` - disable event streaming
    - `app` - stream to application
    - `file:/absolute/path/to/events.log` - stream to file
    - Static text message

- **Encrypted secrets** (`secrets/.env.sops.json`, committable):
  - `MISE_SOPS_AGE_KEY_FILE` auto-set to `~/.config/sops/age/keys.txt` when present
  - Decrypted on-demand by mise when loading env

### Setup Examples

Local overrides:
```bash
cp mise.local.toml.example mise.local.toml
# edit with local values
```

Encrypted secrets:
```bash
cp secrets/.env.json.example secrets/.env.json
# edit secrets/.env.json with real values (gitignored)
make secrets-sops-json
```

This generates `secrets/.env.sops.json` from your local age key and can be safely committed.

## Defaults included

### Terminal & Editor
- Alacritty with Catppuccin dark (mocha) theme (installed from source via cargo)
- Default IDE: Zed (`ide` shell alias → `zed .` when available)
- Desktop macOS apps via casks: Raycast, Zed, Warp, GitHub Desktop, Codex, Claude Code
- Managed editor configs for Zed; VSCode/Cursor available as optional stow packages
- Neovim with NvChad + Avante plugin scaffold

### Language Tooling
- Rust 1.91 via mise with extended devtools:
  - Build/test: `bacon`, `cargo-nextest`, `cargo-watch`, `trunk`
  - Performance: `sccache`, `cargo-chef`, `cargo-llvm-cov`, `hyperfine`
  - Quality: `cargo-deny`, `cargo-audit`, `cargo-expand`, `cargo-machete`, `cargo-criterion`, `rust-script`
- Local Rust crate `toolz` (in `toolz/`) installs to `~/.local/bin/toolz` via `mise run dev-tools` or `mise run toolz-install`
- Python via `uv` (replaces pip/venv workflows)
- Bun-first JS/TS (`bun`, `bunx`) with Node for compatibility

### toolz CLI
`toolz` is a local personal utility binary included in this repo (`toolz/`).

- CLI mode:
  - `toolz sys --dry-run`
  - `toolz log analyze <file>`
  - `toolz ai chat --provider ollama`
  - `toolz db list`
- TUI mode:
  - `toolz` (no arguments)

### Container & K8s
- Local runtime: `colima` (not Docker Desktop)
- K8s stack: `kubectl`, `helm`, `k9s`, `tilt`, `k3d`, `kind`, `stern`
- Docker CLI + compose

### System Utilities
- Health monitoring: `bottom`, `btop`, `procs`, `duf`, `dust`, `scripts/system-health.sh`
- Raycast script commands (macOS) via `scripts/setup-macos.sh` from `raycast-scripts/`

### AI Tools Integration
Personal MCP + multi-AI config wiring via `scripts/setup-ai-tools.sh`:
- Builds/installs `~/dev/personal-mcp` → `~/.local/bin/personal-mcp`
- Ensures `~/.ctx/handoffs` and `~/.ctx/chats` directories
- Configures MCP server entries for: Claude Desktop, Claude Code, Cursor, Zed, Codex, OpenCode, Gemini
- BAML MCP tools: `baml_init`, `baml_generate`, `baml_test` (via `baml-cli`/`bunx` fallback)
- Seeds AI tool configs (merge-only, no overwrites):
  - `~/.claude/settings.json`
  - `~/.config/opencode/opencode.json`
  - `~/.codex/config.toml` (seed only if missing)
  - `~/.gemini/settings.json`
- Standard MCP/BAML env defaults:
  - `MCP_ENV_FILE=~/.config/dev-bootstrap/secrets.env`
  - `BAML_LOG=info`
  - `BOUNDARY_MAX_LOG_CHUNK_CHARS=3000`
- No API keys written (use secrets.env or mise.local.toml)

### Companion Projects
- `personal-mcp` (Rust): MCP server with BAML tools
- `dumcp` (Go): Utility tooling
- `maestro-dev` (Shell/Docker): Development workflow orchestration

## Tooling policy

### General Principles
- Prefer open-source CLI tools by default
- Rust-native tools where practical (`rg`, `fd`, `bat`, `eza`, `bacon`, `cargo-nextest`, `cargo-watch`, `trunk`)
- Declarative package management via Nix flake for CLI tools
- Version-managed runtimes via mise (not nvm/pyenv/rustup directly)

### Language Workflows
- Python: `uv` over raw `python`/`pip` (`uv run`, `uv pip`, `uv venv`, `uvx`)
- JavaScript/TypeScript: `bun`/`bunx` over `npm`/`npx`/`pnpm`/`yarn` where compatible
- Rust: mise-managed toolchain (currently 1.91) + cargo for builds

### Package Management
- CLI tools: Nix flake (declarative, reproducible)
- Homebrew: Casks + macOS-specific tools + container stack
- `zerobrew` (`zb`): Fast companion for Homebrew-compatible commands (`install`, `bundle`, `list`, `info`)
- `mise`: Language runtime version management

### Container Runtime
- `colima` for local development (not Docker Desktop)
- Docker CLI + compose via Homebrew

### Proprietary Exceptions
Explicit and minimal:
- Raycast (macOS UX workflow requirement)
- AI developer tools (Claude Code, Codex, OpenCode, Gemini CLI)
- Security tooling as explicitly chosen (e.g., password managers)

## Centralized AI logs (Vector)

- Enable local `vector` stow package via `config/stow-packages.local.txt`.
- Sources: Claude Code, Codex, OpenCode, Gemini CLI.
- The Vector config writes normalized logs to:
  - `~/logs/ai/<agent>/<YYYY-MM-DD>/<session>/events.jsonl`
  - `agent` is `claude`, `codex`, `opencode`, or `gemini`
- Useful tasks:
  - `mise run logs-central-validate`
  - `mise run logs-central-run`
  - `mise run logs-central-dashboard` (serves `http://127.0.0.1:8765`)
  - `mise run logs-central-service-install`
  - `mise run logs-central-service-status`
  - `mise run logs-central-service-logs`
  - `mise run logs-central-service-stop`
  - `mise run logs-central-service-uninstall`
  - `mise run logs-central-retention-service-install`
  - `mise run logs-central-retention-service-status`
  - `mise run logs-central-retention-service-run-now`
  - `mise run logs-central-retention-service-logs`
  - `mise run logs-central-retention-service-uninstall`
  - `mise run logs-central-retention`
  - `mise run logs-central-retention-dry`
- Retention defaults are customizable with env vars:
  - `AI_LOG_RETENTION_DAYS` (default: `180`)
  - `AI_LOG_COMPRESS_AFTER_DAYS` (default: `14`)
  - `AI_LOG_ROOT` (default: `~/logs/ai`)
  - Scheduler time vars: `VECTOR_RETENTION_HOUR` and `VECTOR_RETENTION_MINUTE`

## Documentation

The dotfiles repository has comprehensive documentation covering all aspects of the system:

**Core Documentation:**
- `README.md` - This file (getting started, overview)
- `CLAUDE.md` - Project instructions for Claude Code (AI assistant guidance)
- `AGENTS.md` - Agent workflow instructions (bd/beads task management)

**Technical Documentation:**
- `SCRIPTS.md` - Comprehensive script architecture and conventions
- `scripts/lib/README.md` - Shared library API reference and migration guide
- `tests/README.md` - Testing infrastructure and coverage documentation
- `.github/workflows/README.md` - CI/CD pipeline documentation and strategy

## Notes

**Platform Support:**
- Primary focus on macOS, with Linux support for core functionality
- Platform-aware testing (macOS-specific tests skip gracefully on Linux)

**Testing & Quality:**
- All shared libraries have comprehensive test coverage (102 bats tests)
- Automated testing on every push/PR with fast minimal CI
- Comprehensive weekly tests (all platforms, all checks)
- All scripts follow consistent conventions and pass shellcheck
- Continuous integration via GitHub Actions (minimal + comprehensive workflows)

**Script Architecture:**
- Shared libraries provide reusable utilities (log, cmd, pkg, dryrun, json, launchd)
- Consistent conventions across all scripts (set -euo pipefail, standard header, error handling)
- Phase 2 migrations completed (command checking, dry-run standardization)
- See `SCRIPTS.md` for comprehensive architecture documentation
- Raycast is macOS-only and requires a supported macOS version
- Zed, Warp, and GitHub Desktop are installed only on environments that support Homebrew casks
- Enable optional VSCode/Cursor managed configs by adding `vscode` and `cursor` to `config/stow-packages.local.txt`
- Avante defaults to OpenAI; set `OPENAI_API_KEY` before use
- `raycast`, `mcpm`, and `vector` are local-only by default; enable via `config/stow-packages.local.txt` when needed
- On macOS, run containers with `colima` (lighter than Docker Desktop). Use `scripts/container-dev.sh` or `make container-start`
- For non-interactive bootstrap, set `GIT_USER_NAME` and `GIT_USER_EMAIL` to avoid git identity prompts
- Shell git shortcuts default to GitHub CLI credential flow:
  - `gp` => push with `gh auth git-credential`
  - `gl` => pull `--ff-only` with `gh auth git-credential`
  - `gpf` => push `--force-with-lease` with `gh auth git-credential`
- Git Flow is included via `git-flow-next` (maintained) with shortcuts:
  - `gfi` (init), `gffs`/`gfff` (feature start/finish)
  - `gfrs`/`gfrf` (release start/finish), `gfhs`/`gfhf` (hotfix start/finish)
