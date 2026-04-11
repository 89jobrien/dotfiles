---
name: maestro-dev-setup
description: Use when setting up a new developer workstation for the Maestro project, when a developer reports missing tools or broken auth, or when onboarding someone to Maestro development
---

# Maestro Dev Setup

Systematic setup of a macOS workstation for Maestro development. Check everything first, install in parallel, configure auth, verify.

## References

- [references/tool-versions.md](references/tool-versions.md) — Required/optional tool versions, GKE cluster details, API endpoints
- [references/macos-gotchas.md](references/macos-gotchas.md) — Common macOS issues (Colima, gcloud PATH, npm/bun alias, Apple Silicon)

## Tools

- [tools/check-prereqs.sh](tools/check-prereqs.sh) — Check all prerequisites and report status. Run with `--install` to auto-install missing tools.
- [tools/setup-gke-auth.sh](tools/setup-gke-auth.sh) — Interactive gcloud auth + kubectl context setup for the Maestro GKE cluster.

## Prerequisites Check

Run the prereqs checker or check manually:

```bash
./tools/check-prereqs.sh            # Check status
./tools/check-prereqs.sh --install   # Check and install missing
```

Manual check table:

| Tool | Check | Install (Homebrew) |
|------|-------|---------------------|
| Rust | `rustc --version` | [rustup.rs](https://rustup.rs) |
| Docker | `docker --version` | `brew install colima docker` |
| kubectl | `kubectl version --client` | `brew install kubectl` |
| gcloud | `gcloud --version` | `brew install --cask google-cloud-sdk` |
| Helm | `helm version --short` | `brew install helm` |
| gh | `gh --version` | `brew install gh` |
| Node.js | `node --version` | `brew install node` |
| jq | `jq --version` | `brew install jq` |
| cargo-nextest | `cargo nextest --version` | `cargo install cargo-nextest --locked` |

## Setup Steps

### 1. Install missing tools

Install anything missing from the table above. Run independent installs in parallel (brew installs, cargo installs).

### 2. gcloud PATH (macOS/Homebrew)

After installing gcloud, add to `~/.zshrc`:

```bash
export PATH="/opt/homebrew/share/google-cloud-sdk/bin:$PATH"
```

### 3. Authenticate gcloud + configure kubectl

Use the setup script or run manually:

```bash
./tools/setup-gke-auth.sh
```

Or manually:

```bash
gcloud auth login
gcloud components install gke-gcloud-auth-plugin --quiet
gcloud container clusters get-credentials main-0 --region us-east1 --project toptal-maestro
```

Verify: `kubectl config current-context` should return `gke_toptal-maestro_us-east1_main-0`

### 4. Authenticate Maestro CLI

```bash
export MAESTRO_API_URL="https://api.maestro-staging.toptal.net"
maestro auth login
```

### 5. Start Docker

```bash
colima start
```

### 6. Dev tooling and git hooks

```bash
cd <repo-root>   # /path/to/maestro
make dev-setup    # installs cargo-watch
make install-hooks
```

### 7. Build and verify

```bash
make build        # builds both API and CLI
maestro --version
maestro auth status
```

## Quick Verification

Single block to confirm everything works:

```bash
rustc --version && docker --version && kubectl config current-context && \
helm version --short && gh --version && node --version && \
cargo nextest --version && maestro --version && maestro auth status
```

## Common Issues

See [references/macos-gotchas.md](references/macos-gotchas.md) for detailed explanations.

| Issue | Fix |
|-------|-----|
| `npm` aliased to `bun` | Real npm at `/opt/homebrew/bin/npm`. Use full path or remove alias. |
| Docker socket not found | Start Colima: `colima start` |
| kubectl "current-context is not set" | Run step 3 (gcloud get-credentials) |
| gcloud not found after install | Add PATH to `~/.zshrc` (step 2) and source it |
| Colima shell function warnings | Cosmetic — docker still works through the wrapper |
| `maestro auth` expired | Re-run `maestro auth login` with correct `MAESTRO_API_URL` |
