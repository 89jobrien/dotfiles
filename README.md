# Dotfiles

Reproducible dev environment bootstrap with a managed (immutable) core and local (mutable) overrides.

## Quick start

```bash
cd ~/dotfiles
pj dot install
```

Equivalent:

```bash
pj dot install
```

From anywhere (for example from `~`), use:

```bash
pj dot install
```

Recent run log:
- `docs/2026-02-27-bootstrap-runbook.md`

Preferred interfaces:
- Human workflow: `mise run <task>`
- AI/automation workflow: `just <recipe>`
- `make` remains as compatibility wrapper.
- Bootstrap entrypoint: `pj dot install` (includes stow conflict prompts + backup flow).

## What bootstrap does

- Installs packages via `zerobrew` (`zb bundle`) when available, with `brew bundle` fallback (`Brewfile.macos` on macOS, `Brewfile.linux` on Linux, fallback `Brewfile`).
- Installs language runtimes via `mise` (`node`, `bun`, `python`, `uv`, `go`, `rust`) to avoid Brew/runtime version drift.
- Installs `zerobrew` (`zb`) first (when available) as a fast companion tool for Homebrew workflows.
- Falls back to `apt` on Linux if Homebrew is unavailable (`config/apt-packages.txt`).
- Stows default managed packages from `config/stow-packages.txt`.
- Runs post-setup hooks:
  - `scripts/setup-git-config.sh` (configure global git identity + `gh` credential helper + sane push defaults)
  - `scripts/setup-oh-my-zsh.sh` (installs Oh My Zsh unattended, keeps managed `.zshrc`)
  - `scripts/setup-secrets.sh` (decrypt secrets + install pre-commit secret policy)
  - `scripts/setup-macos.sh` (Alacritty file handlers + Raycast script linking on macOS)
  - `scripts/setup-ai-tools.sh` (install personal MCP + seed/merge AI tool configs)
  - `scripts/setup-maestro.sh` (clone/update Maestro repo and run bootstrap mode)
  - `scripts/setup-dev-tools.sh` (Rust/Python CLI tooling)
  - `scripts/setup-nvchad-avante.sh` (Neovim + NvChad + Avante)
  - optional `scripts/post-bootstrap.local.sh` (local only)

## Managed vs local

Managed (commit to repo):
- `config/stow-packages.txt`
- `Brewfile.macos`, `Brewfile.linux`
- dotfile package directories (`git`, `zsh`, `fish`, `alacritty`, `zed`, ...)

Local mutable (not committed):
- `config/stow-packages.local.txt` (copy from `config/stow-packages.local.example.txt`)
- `config/apt-packages.local.txt` (copy from `config/apt-packages.local.example.txt`)
- `scripts/post-bootstrap.local.sh` (copy from `scripts/post-bootstrap.local.example.sh`)
- `~/.zshrc.local` (already sourced by `zsh/.zshrc`)
- local app state packages (`raycast`, `mcpm`, `vector`)

## Day-2 commands

```bash
mise run up                # start container runtime + k3d + doctor
mise run doctor            # validate required tools
mise run drift             # detect repo and stow drift
mise run stow              # restow managed config only
mise run post              # rerun post-setup hooks only
mise run nvim              # rerun NvChad + Avante setup
mise run container-start
mise run container-status
mise run compose-up
mise run compose-status
mise run k3d-up            # or: mise run kind-up
mise run tilt-up
mise run observe               # one-shot summary of runtime + pods + containers
mise run observe-k8s           # open k9s UI
mise run observe-logs          # tail all k8s logs with stern
mise run observe-docker        # live-refresh docker ps
mise run observe-docker-events # stream docker events
mise run observe-docker-stats  # stream docker stats
mise run health                # system summary (cpu/mem/disk/procs)
mise run health-live           # interactive monitor
mise run raycast-scripts       # link managed raycast script commands
mise run personal-mcp          # install + wire personal MCP into Claude/Cursor/Zed
mise run ai-config             # seed/merge Claude/OpenCode/Codex/Gemini configs
mise run maestro-setup         # clone/update Maestro + run setup mode
mise run maestro-doctor        # verify Maestro repo + prerequisites
mise run maestro-up            # run Maestro dev setup + ci
mise run maestro-up-quick      # run Maestro dev setup only
mise run maestro-up-api        # run setup + ci + api-run
mise run maestro-handoff       # write private handoff context
```

From `~`, for manual commands:

```bash
make -C ~/dotfiles observe
make -C ~/dotfiles observe-k8s
make -C ~/dotfiles observe-logs
```

For automation/agents in repo:

```bash
just up
just doctor
just compose-up
just observe-k8s
just maestro-doctor
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

`mise` is configured to load local env files without committing secrets:

- Committed config: `.mise.toml`
  - loads `[".env", ".env.local", "secrets/.env.json", "secrets/.env.sops.json"]`
  - extends PATH for common project bins
  - auto-creates `.venv` for Python workflows
  - sets `pj` TUI defaults (`PJ_TUI_EVENT_STREAM=app`, `PJ_TUI_EVENT_MAX_CHARS=140`)
- Local-only overrides: `mise.local.toml` (gitignored)
  - copy from `mise.local.toml.example`
  - use `__SECRET_*` keys for masked `mise env` output
  - override `PJ_TUI_EVENT_STREAM` with:
    - `off`
    - `app`
    - `file:/absolute/path/to/events.log`
    - a static text message
- Encrypted option:
  - store secrets as `secrets/.env.sops.json` (committable encrypted file)
  - `MISE_SOPS_AGE_KEY_FILE` is auto-set to `~/.config/sops/age/keys.txt` when present

Example setup:

```bash
cp mise.local.toml.example mise.local.toml
# edit with local values
```

Sops JSON flow:

```bash
cp secrets/.env.json.example secrets/.env.json
# edit secrets/.env.json with real values (gitignored)
make secrets-sops-json
```

This generates `secrets/.env.sops.json` from your local age key and can be safely committed.

## Defaults included

- Alacritty with Catppuccin dark (mocha) theme.
- Alacritty installed from source (cargo build/install), not Homebrew cask.
- Default IDE preference: Zed (`ide` shell alias points to `zed .` when available).
- Desktop macOS apps via casks: Raycast, Zed, Warp, GitHub Desktop, Codex, Claude Code.
- Managed editor configs for Zed, with VSCode/Cursor configs available as optional stow packages.
- Neovim with NvChad + Avante plugin scaffold.
- Rust-focused tooling (`mise`, `bacon`, `cargo-nextest`, `cargo-watch`, `trunk`) and Python `uv`.
- Bun-first JS/TS tooling (`bun`, `bunx`) with Node kept for compatibility.
- Extended Rust devtools (`sccache`, `cargo-chef`, `cargo-llvm-cov`, `cargo-deny`, `cargo-audit`, `cargo-expand`, `cargo-machete`, `cargo-criterion`, `hyperfine`, `rust-script`).
- Container + local K8s stack (`colima`, Docker CLI, `kubectl`, `helm`, `k9s`, `tilt`, `k3d`, `kind`, `stern`).
- System health stack (`bottom`, `btop`, `procs`, `duf`, `dust`) plus `scripts/system-health.sh`.
- Raycast script commands wired via `scripts/setup-macos.sh` from `raycast-scripts/`.
- Personal MCP + AI config wiring via `scripts/setup-ai-tools.sh`:
  - installs `~/dev/personal-mcp` to `~/.local/bin/personal-mcp`
  - ensures `~/.ctx/handoffs` and `~/.ctx/chats`
  - configures MCP server entry for Claude Desktop, Cursor, Zed, Codex, OpenCode, and Gemini
  - includes BAML MCP tools (`baml_init`, `baml_generate`, `baml_test`) with `baml-cli`/`bunx` fallback
- AI config seeding (also in `scripts/setup-ai-tools.sh`):
  - `~/.claude/settings.json`
  - `~/.config/opencode/opencode.json`
  - `~/.codex/config.toml` (seed only if missing)
  - `~/.gemini/settings.json`
  - standard MCP/BAML env defaults:
    - `MCP_ENV_FILE=~/.config/dev-bootstrap/secrets.env`
    - `BAML_LOG=info`
    - `BOUNDARY_MAX_LOG_CHUNK_CHARS=3000`
  - no API keys written by this script
- Maestro helper workflow via `scripts/maestro-dev.sh`:
  - path from `DOT_MAESTRO_DIR` (fallback `PJ_MAESTRO_DIR`, then `~/Documents/GitHub/maestro`)
  - handoff path from `DOT_PRIVATE_CTX_DIR` (fallback `PJ_PRIVATE_CTX_DIR`, then `~/.ctx/handoffs`)
  - commands: `where`, `doctor`, `up [--quick] [--api-run]`, `handoff`
- Maestro bootstrap hook via `scripts/setup-maestro.sh`:
  - `DOT_MAESTRO_DIR` (fallback `PJ_MAESTRO_DIR`, then `~/Documents/GitHub/maestro`)
  - `DOT_MAESTRO_REPO` for first-time clone (accepts `owner/repo` with `gh`, or git URL)
  - `DOT_MAESTRO_MODE`: `quick` (default), `full`, `api`, `none`

## Tooling policy

- Prefer open-source CLI tools by default.
- Prefer Rust-native tools where practical (`ripgrep`, `fd`, `bat`, `eza`, `bacon`, `cargo-nextest`, `cargo-watch`, `trunk`).
- Prefer `uv` over raw `python`/`pip` for Python workflows (`uv run`, `uv pip`, `uv venv`, `uvx`).
- Prefer `bun`/`bunx` over `npm`/`npx`/`pnpm`/`yarn` for JS workflows where compatible.
- Prefer `zerobrew` (`zb`) for Homebrew-compatible commands (`install`, `bundle`, `list`, `info`) and fall back to `brew` for non-parity operations.
- Keep proprietary exceptions explicit and minimal:
  - Raycast (required UX workflow on macOS)
  - Any local security tooling you explicitly choose (for example password managers)

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

## Notes

- Raycast is macOS-only and requires a supported macOS version.
- Zed, Warp, and GitHub Desktop are installed only on environments that support Homebrew casks.
- Enable optional VSCode/Cursor managed configs by adding `vscode` and `cursor` to `config/stow-packages.local.txt`.
- Avante defaults to OpenAI; set `OPENAI_API_KEY` before use.
- `raycast`, `mcpm`, and `vector` are local-only by default; enable via `config/stow-packages.local.txt` when needed.
- On macOS, run containers with `colima` (lighter than Docker Desktop). Use `scripts/container-dev.sh` or `make container-start`.
- For non-interactive bootstrap, set `GIT_USER_NAME` and `GIT_USER_EMAIL` to avoid git identity prompts.
- Shell git shortcuts default to GitHub CLI credential flow:
  - `gp` => push with `gh auth git-credential`
  - `gl` => pull `--ff-only` with `gh auth git-credential`
  - `gpf` => push `--force-with-lease` with `gh auth git-credential`
- Git Flow is included via `git-flow-next` (maintained) with shortcuts:
  - `gfi` (init), `gffs`/`gfff` (feature start/finish)
  - `gfrs`/`gfrf` (release start/finish), `gfhs`/`gfhf` (hotfix start/finish)
