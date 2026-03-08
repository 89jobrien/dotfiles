# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A dotfiles repo that bootstraps a reproducible dev environment on macOS/Linux. Uses GNU Stow for symlink management, Homebrew/apt for packages, and mise for language runtimes. The primary entrypoint is `pj dot install` (which calls `install.sh` → `scripts/bootstrap.sh`).

## Key Commands

```bash
# Full bootstrap (preferred entry)
pj dot install
# Bypass pj requirement
ALLOW_DIRECT_DOTFILES_INSTALL=1 ./install.sh

# Partial bootstrap
./install.sh --no-packages --no-stow    # post-hooks only
./install.sh --no-packages --no-post    # stow only

# Validation
mise run doctor          # check all required tools are present
mise run drift           # detect uncommitted changes + stow conflicts

# Individual post-hooks
mise run ai-tools        # install personal-mcp + configure all AI tool configs
mise run macos           # macOS defaults + Raycast script linking
mise run dev-tools       # cargo/bun tool installs

# Secrets
mise run secrets-check   # verify no plaintext secrets staged

# Testing & quality
mise run test            # run all bats unit tests
mise run test-lib        # run library tests only (tests/lib/*.bats)
mise run shellcheck      # shellcheck all scripts in scripts/

# toolz crate
mise run toolz-install   # build + install toolz to ~/.local/bin/toolz
mise run toolz-dev       # cargo build (no install)

# Interactive
mise run menu            # interactive TUI to explore and run commands
```

Three equivalent task runners: `mise run <task>` (interactive), `just <recipe>` (automation/agents), `make <target>` (compat wrapper). Task definitions live in `.mise.toml`, `Justfile`, and `Makefile` respectively.

## Issue Tracking

Uses `bd` (beads) for issue tracking. See `AGENTS.md` for the full agent workflow including mandatory push-before-done rules.

```bash
bd ready              # find available work
bd show <id>          # view issue details
bd update <id> --status in_progress
bd close <id>
bd sync               # sync with git
```

## Architecture

### Bootstrap Flow

`install.sh` delegates to `pj dot install` when `pj` is available, otherwise runs `scripts/bootstrap.sh` directly. Bootstrap executes in order:

1. `setup-zerobrew.sh` (pre-homebrew fast companion)
2. `zerobrew` (`zb`) package install (`zb bundle install --file Brewfile.macos/Brewfile.linux`); falls back to `brew bundle`, then `apt` on Linux
3. `setup-npm-tools.sh` (npm packages via standard Homebrew — runs immediately after packages)
4. `mise install` (language runtimes from `.mise.toml`)
5. Stow symlinks (packages from `config/stow-packages.txt`)
6. Post-hooks in section order: Shell (`setup-git-config.sh` then `setup-oh-my-zsh.sh`) → Secrets → Nix → macOS → AI Tools (`setup-ai-tools.sh` + `setup-hooks.sh`) → Maestro → Companion Repos → Dev Tools → Editor → Local (if `scripts/post-bootstrap.local.sh` exists)
7. Summary table printed at end

### `brew()` Shell Shim

The `brew()` function in `.zshrc` routes `install|bundle|uninstall|list|info` to `zb` first, falling back to real Homebrew on failure. All other subcommands go directly to Homebrew. The `_brew_real()` helper resolves the Homebrew binary path (`/opt/homebrew/bin/brew` → `/usr/local/bin/brew`).

### Shared Logging Library

All scripts source `scripts/lib/log.sh` and set `TAG="name"` at the top. Available functions: `log`, `log_ok`, `log_skip`, `log_warn`, `log_err`, `spin`, `section`. Uses `gum` colors when available + TTY, plain printf otherwise.

### Script Conventions

- Every script starts with `set -euo pipefail` and sources `scripts/lib/log.sh`
- `ROOT_DIR` always points to the repo root via `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)`
- Post-hook scripts exit 0 on skip (not failure) so bootstrap continues
- Bootstrap wraps each hook in `run_hook "Name" script` which captures exit codes for the summary

**Library source order** (log.sh must be first; others as needed):
1. `log.sh` — logging (required; others may call it)
2. `cmd.sh` — `has_cmd`, `require_cmd`, `check_cmd`, `ensure_cmd`
3. `pkg.sh` — package manager detection
4. `dryrun.sh` — `set_dryrun_mode`, `dryrun_exec` (for destructive ops)
5. `json.sh` — `merge_json_config` for jq-based read-modify-write
6. `launchd.sh` — macOS service management (`launchd_start`, `launchd_stop`, `launchd_status`)
7. `obfuscate.sh` — secret redaction (`obfuscate_text`, `obfuscate_file`); auto-used by `log.sh` bootstrap output
8. `common.sh` — shared utility functions

See `SCRIPTS.md` for the full library reference and script template.

### Managed vs Local Layer

Committed (immutable): `config/stow-packages.txt`, `Brewfile.*`, dotfile package dirs (`git/`, `zsh/`, `alacritty/`, `zed/`)

Gitignored (mutable): `config/stow-packages.local.txt`, `mise.local.toml`, `scripts/post-bootstrap.local.sh`, `secrets/*.env`

### Stow Packages

Each top-level directory that appears in `config/stow-packages.txt` is a stow package. Its contents mirror `$HOME` structure (e.g., `zsh/.zshrc` becomes `~/.zshrc`). Stow does a dry-run conflict check before linking.

### Secrets

Encrypted with `sops + age`. Decrypted to `~/.config/dev-bootstrap/secrets.env` (chmod 600). A pre-commit hook in `.githooks/pre-commit` blocks plaintext secret files from being committed.

### AI Tool Configuration (`setup-ai-tools.sh`)

Single script configures 7 tools: Claude Desktop, Claude Code, Cursor, Zed, OpenCode, Codex, Gemini. Uses `merge_json_config()` helper for JSON configs (jq-based read-modify-write). Codex uses TOML via awk strip+append. Builds `personal-mcp` binary from `~/dev/personal-mcp` if the repo exists.

### Nix Flake (`flake.nix`)

Declarative CLI tools layer that sits alongside Homebrew. Installs a single `buildEnv` profile entry bundling ~30 CLI tools via `nix profile install .#default`. The setup script (`scripts/setup-nix.sh`) installs Nix itself (Determinate Systems installer) then installs or upgrades the profile. Runs as a bootstrap post-hook after Secrets.

```bash
mise run nix-install     # install Nix + apply flake packages
mise run nix-update      # update nixpkgs lock + reinstall
mise run nix-check       # verify profile + flake
```

To add a package: find the nixpkgs attr name (`nix search nixpkgs <term>`), add to `cliPackages` in `flake.nix`, run `mise run nix-install`. To list installed binaries: `ls ~/.nix-profile/bin/`.

Brewfile entries tagged `# [nix-batch-1]` are the first migration wave (kept in both during transition). What stays in Brew: casks, container stack, macOS-only tools, tools not in nixpkgs, and runtimes managed by mise.

### toolz Crate (`toolz/`)

Embedded Rust crate at `toolz/` — personal swiss-army CLI (sys, log, ai, db subcommands). Uses ratatui for TUI screens, tokio for async, fastembed for ONNX-based RAG. Installed to `~/.local/bin/toolz` via `mise run toolz-install`. First build is slow due to fastembed's ONNX transitive deps.

### Companion Projects

These projects live outside the dotfiles repo but depend on tools the dotfiles provide:

| Project | Path | Repo | Language | Tools from dotfiles |
|---|---|---|---|---|
| personal-mcp | `~/dev/personal-mcp` | `89jobrien/personal-mcp` | Rust | `cargo`/`rust` (mise), `baml-cli` (dev-tools), `jq`, `just` (nix) |
| dumcp | `~/dev/dumcp` | `89jobrien/dumcp` | Go | `go` (mise) |
| obfsck | `~/dev/obfsck` | `89jobrien/obfsck` | Rust | `cargo`/`rust` (mise) |
| maestro-dev | `~/maestro-dev` | `89jobrien/maestro-dev` | Shell/Docker | `docker`/`colima` (brew), `tmux`, `just` (nix) |

All four are private repos. Bootstrap clones them via `scripts/setup-companion-repos.sh`.

Runtime runtimes (Go, Rust) are managed by mise. CLI tools (`tmux`, `just`, `jq`, etc.) come from the Nix flake. Container tooling (`docker`, `colima`) stays in Homebrew.

## Tooling Preferences

- Rust-native CLI tools preferred (`rg`, `fd`, `eza`, `bacon`, `cargo-nextest`)
- `uv` over `pip` for Python; `bun`/`bunx` over `npm`/`npx` for JS
- `colima` for containers (not Docker Desktop)
- `mise` for runtime version management (not nvm/pyenv/rustup directly)
- `gum` for interactive TUI elements in scripts
- `obfsck` for secret redaction and identifier obfuscation in logs (installed from `~/dev/obfsck` during bootstrap)

## Modifying Scripts

When adding a new post-hook script:
1. Source `scripts/lib/log.sh` (and other libs as needed) and set `TAG`
2. Add a `run_hook` call in `scripts/bootstrap.sh` under the appropriate section
3. Add a mise task in `.mise.toml` and matching entries in `Justfile`/`Makefile`

When modifying AI tool configs: all 7 tools are configured in `setup-ai-tools.sh`. Don't create separate per-tool scripts.

When adding shared library functions: add bats tests in `tests/lib/` and update `scripts/lib/README.md`.
