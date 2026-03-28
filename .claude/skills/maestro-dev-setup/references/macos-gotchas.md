# macOS Setup Gotchas

Common issues encountered when setting up Maestro development on macOS (Apple Silicon).

## Docker via Colima

Colima provides Docker on macOS without Docker Desktop.

**Shell function warnings:**
```
zsh: command not found: _colima_ensure_running
zsh: command not found: _colima_set_socket
```
These are cosmetic — docker still works. They come from shell functions that wrap `docker` to auto-start Colima. Safe to ignore.

**Colima not running:**
```bash
colima start          # Start with defaults
colima start --cpu 4 --memory 8  # With more resources
colima status         # Check status
```

**Docker socket path:**
Colima uses `~/.colima/docker.sock` instead of `/var/run/docker.sock`. Most tools handle this via Docker context, but if something hardcodes the socket path, set:
```bash
export DOCKER_HOST="unix://$HOME/.colima/docker.sock"
```

## gcloud CLI (Homebrew)

**PATH not set after install:**
Homebrew cask installs gcloud to `/opt/homebrew/share/google-cloud-sdk/bin/`. Add to `~/.zshrc`:
```bash
export PATH="/opt/homebrew/share/google-cloud-sdk/bin:$PATH"
```

**Shell completions (optional):**
```bash
source "/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc"
source "/opt/homebrew/share/google-cloud-sdk/path.zsh.inc"
```

## npm aliased to bun

Some setups alias `npm` to `bun`. The real npm is at `/opt/homebrew/bin/npm`.

**Check:** `type npm` — if it says "aliased to bun", you're affected.

**Fix options:**
1. Use full path: `/opt/homebrew/bin/npm install`
2. Remove alias from `~/.zshrc` or shell config
3. Use `unalias npm` in current session

**Why it matters:** `maestro-ui` uses npm scripts and `package-lock.json`. Using bun may produce different lockfiles.

## Apple Silicon (ARM64)

Maestro containers built on Apple Silicon produce ARM64 images. When deployed to GKE:
- GKE Autopilot auto-provisions ARM64 nodes (C4A compute class)
- No manual configuration needed
- Cross-architecture builds not required for staging/production
