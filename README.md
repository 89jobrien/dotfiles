# Dotfiles

Reproducible dev environment bootstrap with a managed (immutable) core and local (mutable) overrides.

## Quick start

```bash
cd ~/dotfiles
./install.sh
```

Equivalent:

```bash
make install
# or:
mise run install
```

From anywhere (for example from `~`), use:

```bash
make -C ~/dotfiles install
```

Preferred interfaces:
- Human workflow: `mise run <task>`
- AI/automation workflow: `just <recipe>`
- `make` remains as compatibility wrapper.

## What bootstrap does

- Installs packages via Homebrew (`Brewfile.macos` on macOS, `Brewfile.linux` on Linux, fallback `Brewfile`).
- Installs `zerobrew` (`zb`) first (when available) as a fast companion tool for Homebrew workflows.
- Falls back to `apt` on Linux if Homebrew is unavailable (`config/apt-packages.txt`).
- Stows default managed packages from `config/stow-packages.txt`.
- Runs post-setup hooks:
  - `scripts/macos-defaults.sh` (Alacritty defaults on macOS)
  - `scripts/setup-dev-tools.sh` (Rust/Python CLI tooling)
  - `scripts/setup-nvchad-avante.sh` (Neovim + NvChad + Avante)
  - optional `scripts/post-bootstrap.local.sh` (local only)

## Managed vs local

Managed (commit to repo):
- `config/stow-packages.txt`
- `Brewfile.macos`, `Brewfile.linux`
- dotfile package directories (`git`, `zsh`, `fish`, `alacritty`, ...)

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
mise run k3d-up            # or: mise run kind-up
mise run tilt-up
mise run observe               # one-shot summary of runtime + pods + containers
mise run observe-k8s           # open k9s UI
mise run observe-logs          # tail all k8s logs with stern
mise run observe-docker        # live-refresh docker ps
mise run observe-docker-events # stream docker events
mise run observe-docker-stats  # stream docker stats
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
just observe-k8s
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
./install.sh
```

This decrypts to `~/.config/dev-bootstrap/secrets.env` (chmod 600), and `zsh/.zshrc` auto-loads it for new shells.

## Mise env + secrets pattern

`mise` is configured to load local env files without committing secrets:

- Committed config: `.mise.toml`
  - loads `[".env", ".env.local", "secrets/.env.json", "secrets/.env.sops.json"]`
  - extends PATH for common project bins
  - auto-creates `.venv` for Python workflows
- Local-only overrides: `mise.local.toml` (gitignored)
  - copy from `mise.local.toml.example`
  - use `__SECRET_*` keys for masked `mise env` output
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
- Raycast cask in macOS Brewfile.
- Neovim with NvChad + Avante plugin scaffold.
- Rust-focused tooling (`mise`, `bacon`, `cargo-nextest`, `cargo-watch`, `trunk`) and Python `uv`.
- Bun-first JS/TS tooling (`bun`, `bunx`) with Node kept for compatibility.
- Extended Rust devtools (`sccache`, `cargo-chef`, `cargo-binstall`, `cargo-llvm-cov`, `cargo-deny`, `cargo-audit`, `cargo-outdated`, `cargo-expand`, `cargo-machete`, `cargo-criterion`, `hyperfine`).
- Container + local K8s stack (`colima`, Docker CLI, `kubectl`, `helm`, `k9s`, `tilt`, `k3d`, `kind`, `stern`).

## Tooling policy

- Prefer open-source CLI tools by default.
- Prefer Rust-native tools where practical (`ripgrep`, `fd`, `bat`, `eza`, `bacon`, `cargo-nextest`, `cargo-watch`, `trunk`).
- Prefer `uv` over raw `python`/`pip` for Python workflows (`uv run`, `uv pip`, `uv venv`, `uvx`).
- Prefer `bun`/`bunx` over `npm`/`npx`/`pnpm`/`yarn` for JS workflows where compatible.
- Use `zerobrew` (`zb`) alongside Homebrew for faster install/search workflows where practical.
- Keep proprietary exceptions explicit and minimal:
  - Raycast (required UX workflow on macOS)
  - Any local security tooling you explicitly choose (for example password managers)

## Notes

- Raycast is macOS-only and requires a supported macOS version.
- Avante defaults to OpenAI; set `OPENAI_API_KEY` before use.
- `raycast`, `mcpm`, and `vector` are local-only by default; enable via `config/stow-packages.local.txt` when needed.
- On macOS, run containers with `colima` (lighter than Docker Desktop). Use `scripts/container-dev.sh` or `make container-start`.
