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
```

Three equivalent task runners: `mise run <task>` (interactive), `just <recipe>` (automation/agents), `make <target>` (compat wrapper). Task definitions live in `.mise.toml`, `Justfile`, and `Makefile` respectively.

## Architecture

### Bootstrap Flow

`install.sh` delegates to `pj dot install` when `pj` is available, otherwise runs `scripts/bootstrap.sh` directly. Bootstrap executes in order:

1. `setup-zerobrew.sh` (pre-homebrew fast companion)
2. `zerobrew` (`zb`) package install (`zb bundle` on `Brewfile.macos`/`Brewfile.linux`) with `brew` fallback, then `apt` fallback on Linux
3. `mise install` (language runtimes from `.mise.toml`)
4. Stow symlinks (packages from `config/stow-packages.txt`)
5. Post-hooks in section order: Shell → Secrets → macOS → AI Tools → Maestro → Dev Tools → Editor
6. Summary table printed at end

### Shared Logging Library

All scripts source `scripts/lib/log.sh` and set `TAG="name"` at the top. Available functions: `log`, `log_ok`, `log_skip`, `log_warn`, `log_err`, `spin`, `section`. Uses `gum` colors when available + TTY, plain printf otherwise.

### Script Conventions

- Every script starts with `set -euo pipefail` and sources `scripts/lib/log.sh`
- `ROOT_DIR` always points to the repo root via `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)`
- Post-hook scripts exit 0 on skip (not failure) so bootstrap continues
- Bootstrap wraps each hook in `run_hook "Name" script` which captures exit codes for the summary

### Managed vs Local Layer

Committed (immutable): `config/stow-packages.txt`, `Brewfile.*`, dotfile package dirs (`git/`, `zsh/`, `alacritty/`, `zed/`)

Gitignored (mutable): `config/stow-packages.local.txt`, `mise.local.toml`, `scripts/post-bootstrap.local.sh`, `secrets/*.env`

### Stow Packages

Each top-level directory that appears in `config/stow-packages.txt` is a stow package. Its contents mirror `$HOME` structure (e.g., `zsh/.zshrc` becomes `~/.zshrc`). Stow does a dry-run conflict check before linking.

### Secrets

Encrypted with `sops + age`. Decrypted to `~/.config/dev-bootstrap/secrets.env` (chmod 600). A pre-commit hook in `.githooks/pre-commit` blocks plaintext secret files from being committed.

### AI Tool Configuration (`setup-ai-tools.sh`)

Single script configures 7 tools: Claude Desktop, Claude Code, Cursor, Zed, OpenCode, Codex, Gemini. Uses `merge_json_config()` helper for JSON configs (jq-based read-modify-write). Codex uses TOML via awk strip+append. Builds `personal-mcp` binary from `~/dev/personal-mcp` if the repo exists.

## Tooling Preferences

- Rust-native CLI tools preferred (`rg`, `fd`, `eza`, `bacon`, `cargo-nextest`)
- `uv` over `pip` for Python; `bun`/`bunx` over `npm`/`npx` for JS
- `colima` for containers (not Docker Desktop)
- `mise` for runtime version management (not nvm/pyenv/rustup directly)
- `gum` for interactive TUI elements in scripts

## Modifying Scripts

When adding a new post-hook script:
1. Source `scripts/lib/log.sh` and set `TAG`
2. Add a `run_hook` call in `scripts/bootstrap.sh` under the appropriate section
3. Add a mise task in `.mise.toml` and matching entries in `Justfile`/`Makefile`

When modifying AI tool configs: all 7 tools are configured in `setup-ai-tools.sh`. Don't create separate per-tool scripts.
